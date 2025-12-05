; ====================================================================
; SMART MEDICATION BOX - ROBUST SAFETY LATCH VERSION (INTERRUPT-DRIVEN)
; DISPENSE BUTTON ? 8259 IR0 ? INTR ? ISR_DISPENSE
; ====================================================================

DATA SEGMENT
    ; --- PORT ADDRESSES ---
    PORTA       EQU 0F0H 
    PORTB       EQU 0F2H 
    PORTC       EQU 0F4H 
    PORT_CON    EQU 0F6H

    PIC_CMD     EQU 0D0H
    PIC_DATA    EQU 0D2H

    ; --- KEYPAD CONSTANTS ---
    K_1         EQU 00H
    K_2         EQU 01H
    K_3         EQU 02H
    K_4         EQU 04H
    K_0         EQU 0DH
    K_STAR      EQU 0CH
    K_HASH      EQU 0EH

    ; --- VARIABLES ---
    TIMER_COUNT       DB 1
    SELECTED_INTERVAL DB 0
    MAX_INTERVALS     DB 0
    INTERVAL_COUNT    DB 0

    ; --- TIMER COUNTERS ---
    T1_Count DB 0
    T2_Count DB 0
    T3_Count DB 0
    T4_Count DB 0
    T5_Count DB 0

    T1_Count_Limit DB 0
    T2_Count_Limit DB 0
    T3_Count_Limit DB 0
    T4_Count_Limit DB 0
    T5_Count_Limit DB 0

    Alarm_flag DB 0
    DISPENSE_REQUEST DB 0

    T1_Set DB 0
    T2_Set DB 0
    T3_Set DB 0
    T4_Set DB 0
    T5_Set DB 0

    T1_Intervals_Count DB 0
    T2_Intervals_Count DB 0
    T3_Intervals_Count DB 0
    T4_Intervals_Count DB 0
    T5_Intervals_Count DB 0
    
    CURRENT_SLOT DB 0

   
    ; --- STRINGS ---
      STR_TITLE1 DB ' MEDICINE TIMER', '$'
      STR_TITLE2      DB '     DISPENSER  ', '$'
     STR_STARTMSG    DB '=Press # to Start=', '$'

    STR_MAIN_MENU     DB 'Press     # to start', '$'
    STR_INT_LINE1     DB 'Select Interval:', '$'
    STR_INT_LINE2     DB '[1] 4Hrs [3] 12Hrs  [2] 8Hrs [4] 24Hrs', '$' 
    STR_INT_CONFIRM   DB 'Interval Set To:', '$'

    TXT_4H   DB '4 Hours', '$'
    TXT_8H   DB '8 Hours', '$'
    TXT_12H  DB '12 Hours', '$'
    TXT_24H  DB '24 Hours', '$'

    STR_ASK_COUNT1   DB 'How many intervals?', '$'
    STR_ASK_COUNT2   DB '(', '$'
    STR_ASK_COUNT3   DB ') Maximum', '$'

    STR_TIMER_SET DB 'Timer set!', '$'
    STR_INSTANCES_OF DB ' instances of', '$'
    STR_HOUR_INTERVAL DB 'Hrs', '$'
    STR_HOUR_INTERVAL2 DB ' Interval', '$'

    STR_NEXT_TIMER1   DB '[#] Next Timer', '$'
    STR_NEXT_TIMER2   DB '[*] Save&Start', '$'

    STR_ALL_TIMERS_SET DB 'System is running', '$'
    STR_DOSE_DISP      DB 'Dose Dispensed!', '$'
    STR_ALARM_MSG      DB 'ALARM! PRESS BTN', '$'

    STR_TIMER_SLOT DB 'Timer set for Slot ', '$'
    
    STR_DOSE_LINE1 DB 'Dose Dispensed', '$'
    STR_DOSE_LINE2 DB 'at Slot ', '$'

STR_ALL_DONE1 DB 'All slots', '$'
STR_ALL_DONE2 DB 'successfully disp.', '$'

STR_DISPENSING DB 'Dispensing...', '$'
    
DATA ENDS


CODE SEGMENT PUBLIC 'CODE'
ASSUME CS:CODE, DS:DATA

; ============================================================
; STARTUP
; ============================================================
START:
    MOV AX, DATA			;Load DATA segment address into AX
    MOV DS, AX			;Set DS = DATA so variables & strings can be accessed

    ; Initialize PIC and ISR
    CALL INIT_PIC
    CALL SET_ISR			; Install interrupt vector for the dispense button (INT 08h)

    ; Configure PPI and LCD
    MOV DX, PORT_CON          ; Select 8255 control register
    MOV AL, 89H               	; Configure PPI ports:
						;  - Port A = Output (LCD data)
						;  - Port B = Output (LCD control, buzzer, motor)
						;  - Port C = Mixed I/O (keypad + signals)
    OUT DX, AL                	; Send configuration to 8255

    ; Initialize LCD
    CALL INIT_LCD             	; Initialize LCD (8-bit mode, cursor OFF, entry mode)
    CALL CLEAR_LCD            	; Clear LCD screen and home cursor

    JMP START_SCREEN      	; go to main menu

; ============================================================
; MAIN MENU SCREEN — GLOBAL LABEL
; ============================================================
START_SCREEN:
    CALL CLEAR_LCD		 ; Clear LCD to prepare the welcome screen

    ; ---- Line 1 EMPTY ----

   ; --------------------------------------------------------
    ; LINE 2 — Display "MEDICINE TIME"
    ; LCD DDRAM address for 2nd row, 1st column = 0C0h
    ; --------------------------------------------------------
    MOV AL, 0C0h              	; Set LCD cursor to row 2, col 1
    CALL INST_CTRL            	; Send command to LCD
    LEA SI, STR_TITLE1        	; Load address of "  MEDICINE TIME   "
    CALL DIS_STR              	; Print the string

   ; --------------------------------------------------------
    ; LINE 3 — Display "DISPENSER"
    ; DDRAM address for 3rd row = 94h on 20x4 LCD
    ; --------------------------------------------------------
    MOV AL, 94h               	; Move cursor to row 3
    CALL INST_CTRL
    LEA SI, STR_TITLE2        	; Load address of "     DISPENSER  "
    CALL DIS_STR              	; Print the string

     ; --------------------------------------------------------
    ; LINE 4 — Display "=Press # to Start="
    ; DDRAM address for row 4 = 0D4h
    ; --------------------------------------------------------
    MOV AL, 0D4h              	; Move cursor to row 4
    CALL INST_CTRL
    LEA SI, STR_STARTMSG    ; Load "=Press # to Start="
    CALL DIS_STR

 ; ------------------------------------------------------------
; Wait until the user presses the '#' key before continuing.
; ------------------------------------------------------------
WAIT_FOR_HASHTAG:
    CALL READ_KEY             	; Read keypad input
    CMP AL, K_HASH            	; Is it '#'? (encoded as 0Eh)
    JNE WAIT_FOR_HASHTAG ; If not '#', keep waiting

    JMP INTERVAL_MENU         ; If '#', move to interval selection

; ============================================================
; PIC INITIALIZATION (8259A)
; Configures PIC for:
; - Edge triggered mode
; - Vector base = 08h
; - IR0 is unmasked (active)
; - All other interrupts blocked
; ============================================================
INIT_PIC:
    CLI					; Disable CPU interrupts during PIC setup

    ; --------------------------------------------------------
    ; ICW1 — Initialization Command Word 1
    ; 11h = 00010001b
    ;  - Bit 4 = 1 ? Begin initialization sequence
    ;  - Bit 0 = 1 ? Edge triggered mode
    ; --------------------------------------------------------
    MOV DX, PIC_CMD		; Select PIC command port (0D0h)
    MOV AL, 11H			; ICW1 value
    OUT DX, AL			; Send command to PIC
   
    ; --------------------------------------------------------
    ; ICW2 — Interrupt Vector Base
    ; PIC interrupt numbers = 08h, 09h, 0Ah, … (IRQ0 = INT 08h)
    ; --------------------------------------------------------
    MOV DX, PIC_DATA            ; Select PIC data port (0D2h)
    MOV AL, 08H                	; ICW2: Base vector = 08h
    OUT DX, AL                 	; Apply ICW2

    ; --------------------------------------------------------
    ; ICW3 — Cascading (not used, single PIC)
    ; 00h = PIC has no slave PICs
    ; --------------------------------------------------------
    MOV AL, 00H                   	; ICW3 value
    OUT DX, AL                 	; Send ICW3

    ; --------------------------------------------------------
    ; ICW4 — Additional settings
    ; 01h = 8086/8088 mode
    ; --------------------------------------------------------
    MOV AL, 01H                	; Use 8086 mode
    OUT DX, AL                 	; Send ICW4

    ; --------------------------------------------------------
    ; OCW1 — Interrupt Mask
    ; 0FFh = mask ALL interrupts temporarily
    ; This prevents accidental triggers during boot
    ; --------------------------------------------------------
    MOV AL, 0FFH               	; Mask all IRQs
    OUT DX, AL                 	; PIC now blocks all interrupts
    CALL DELAY_100MS          ; Small stabilization delay (safety)

    ; --------------------------------------------------------
    ; UNMASK IR0 ONLY
    ; Binary: 1111 1110b = FEh
    ; Enable only IRQ0 (dispense button interrupt)
    ; --------------------------------------------------------
    MOV AL, 0FEH          		; Mask all except IR0
    OUT DX, AL                 	; Now only IR0 can trigger interrupts
    
    STI					; Re-enable global interrupts
    RET					; Return to caller



; ============================================================
; SET_ISR
; Installs custom ISR for INT 08h (IRQ0 from PIC)
; Writes ISR offset and segment into the IVT at 0000:0020
; ============================================================
SET_ISR:
    CLI					; Disable Interrupts during vector update

    MOV AX, 0000h			; IVT segment = 0000h
    MOV ES, AX     		    	; Load ES with IVT segment

   ; --------------------------------------------------------
    ; Write ISR offset at memory 0000:0020
    ; --------------------------------------------------------
    MOV AX, OFFSET ISR_DISPENSE 	; AX = offset of ISR
    MOV ES:[0020h], AX          		; Store at IVT offset 20h (low word)

     ; --------------------------------------------------------
    ; Write ISR segment at memory 0000:0022
    ; --------------------------------------------------------
    MOV AX, SEG ISR_DISPENSE    	; AX = segment of ISR
    MOV ES:[0022h], AX          		; Store at IVT offset 22h (high word)

    STI							; Restore Interrupts
    RET							; Return to Caller

; ============================================================
; INTERVAL MENU
; Displays the "Select Interval" screen
; Waits for keypad input: 1, 2, 3, or 4
; ============================================================
INTERVAL_MENU:
    CALL CLEAR_LCD				;Clear LCD b4 showing menu

     ; --------------------------------------------------------
    ; Display: "Select Interval:"
    ; LCD Line 1 = DDRAM 80h
    ; --------------------------------------------------------
    MOV AL, 80H                 			; Select first line
    CALL INST_CTRL              			; Send instruction to LCD
    LEA SI, STR_INT_LINE1       		; SI = address of the string
    CALL DIS_STR                			; Print "Select Interval:"

   ; --------------------------------------------------------
    ; Display interval options:
    ; [1] 4Hrs [3] 12Hrs
    ; [2] 8Hrs [4] 24Hrs
    ;
    ; LCD Line 2 = DDRAM C0h
    ; --------------------------------------------------------
    MOV AL, 0C0H                			; Select second LCD line
    CALL INST_CTRL            		  	; Send instruction to LCD
    LEA SI, STR_INT_LINE2       		; SI = address of interval options
    CALL DIS_STR                			; Print interval choices

   ;===========================
   ;Waits User choice
   ;============================
WAIT_INTERVAL_KEY:
    CALL READ_KEY				; READ Keypad -> AL = Key code
      
    CMP AL, K_1               		  	; Is key '1' ?
    JE SET_4HR                  			; If yes ? 4 hours
    
    CMP AL, K_2                 			; Is key '2' ?
    JE SET_8HR                  			; If yes ? 8 hours
    
    CMP AL, K_3                 			; Is key '3' ?
    JE SET_12HR                 			; If yes ? 12 hours
    
    CMP AL, K_4                 			; Is key '4' ?
    JE SET_24HR                 			; If yes ? 24 hours
    
    JMP WAIT_INTERVAL_KEY		; Otherwise wait for next key

;==========================
; Storing of the time intervals
;==========================
SET_4HR: 
MOV BYTE PTR SELECTED_INTERVAL, 4	; Store 4hrs
JMP INTERVAL_SELECTED  

SET_8HR:  
MOV BYTE PTR SELECTED_INTERVAL, 8	; Store 8 hrs
JMP INTERVAL_SELECTED 

SET_12HR: 
MOV BYTE PTR SELECTED_INTERVAL,12	; Store 12 hrs
JMP INTERVAL_SELECTED

SET_24HR: 
MOV BYTE PTR SELECTED_INTERVAL,24	; Store 24 hrs
JMP INTERVAL_SELECTED

; ============================================================
; INTERVAL SELECTED
; This section runs after the user selects an interval (4–24 hrs)
; It shows a confirmation message, displays the chosen interval text,
; then moves on to ask "How many intervals?"
; ============================================================
INTERVAL_SELECTED:
    CALL CLEAR_LCD			; Clear LCD
    
    ; Prints "Interval Set to: __"
    MOV AL, 80H				; Prints @ first line
    CALL INST_CTRL			; Send instruction to LCD
    LEA SI, STR_INT_CONFIRM	; gets address of String -> confirmation int msg
    CALL DIS_STR				; Displays String

    ;Shows actual interval text next to the "Interval set to.." string
    MOV AL, 0C0H				;2nd LCD line
    CALL INST_CTRL			; Send command to LCD
    MOV AL, SELECTED_INTERVAL; Load Selected interval into AL
    CALL DISPLAY_INTERVAL_TEXT; Convert number ? text and print it

    CALL DELAY_1S			; Delay for readability

    
    CALL ASK_INTERVAL_COUNT  		; Go to section where user chooses quantity
    CALL STORE_TIMER_SETTINGS           	; Save limits into T1/T2/T3/T4/T5 based on SLOT #
    CALL SHOW_TIMER_CONFIRMATION        ; Display slot assignment: Slot 1, Slot 2, etc.
    RET                                 				; Return to caller (usually back to menu)

    
; ============================================================
; ASK_INTERVAL_COUNT
; This section determines:
;   - The maximum allowed number of intervals (based on hours)
;   - Shows the "(X) Maximum" screen
;   - Waits for valid numeric keypad input
;   - Stores the chosen interval count
; ============================================================
ASK_INTERVAL_COUNT:
    MOV AL, SELECTED_INTERVAL 		; Load the chosen time interval
    
    CMP AL, 4                        				; Is it 4 hours?
    JE L6                             				; ? Yes ? Max = 6

    CMP AL, 8                        				; Is it 8 hours?
    JE L3                             				; ? Yes ? Max = 3

    CMP AL, 12                       				; Is it 12 hours?
    JE L2                             				; ? Yes ? Max = 2

    MOV MAX_INTERVALS, 1             		; Otherwise ? 24 hours ? Max = 1
    JMP SHOW_COUNT                    		; Skip other labels


L6: 
MOV MAX_INTERVALS, 6 				; 4 hrs ? 6 intervals max
JMP SHOW_COUNT

L3: 
MOV MAX_INTERVALS, 3 				; 8 hrs ? 3 intervals max
JMP SHOW_COUNT

L2: 
MOV MAX_INTERVALS, 2				; 12 hrs ? 2 intervals max
JMP SHOW_COUNT

;==========================
;Display "How many intervals?"
;==========================
SHOW_COUNT:
    CALL CLEAR_LCD					;Clear Screen
    
    ;HOW MANY INTERVALS prompt
    MOV AL, 80H						;First line of LCD
    CALL INST_CTRL					; Send instructions to LCD
    LEA SI, STR_ASK_COUNT1			;gets address of STR_ASK_COUNT1
    CALL DIS_STR						; Display string

    ;Shows Maximum No. of intervals =====================
    ; "(" <-- print
    MOV AL, 0C0H						;2nd line of LCD
    CALL INST_CTRL
    LEA SI, STR_ASK_COUNT2			; gets address of string
    CALL DIS_STR						;display string

    MOV AL, MAX_INTERVALS			; Load max no. of interval
    ADD AL,'0'							;Convert No. --> ASCII Digit
    CALL DATA_CTRL					;Print Number

    LEA SI, STR_ASK_COUNT3			; gets address of string
    CALL DIS_STR						; prints ") Maximum"

WAIT_INPUT:
    CALL READ_KEY					;Get keypad value
    
    ;Rejects invalid inputs 
    CMP AL, K_HASH 
    JE WAIT_INPUT
    CMP AL, K_STAR 
    JE WAIT_INPUT
    CMP AL, 9      
    JA WAIT_INPUT

    INC AL								;Convert key value: 0?1, 1?2, etc.
									; dis is bcoz raw key values are 
									;AL-1
									;with INC AL, it ensures in getting the
									;correct no. of intervals
									
    CMP AL, MAX_INTERVALS 			
    JA WAIT_INPUT						; If user selected too many ? retry

    MOV INTERVAL_COUNT, AL			; Save user input
    RET								; Return to caller
   

; ============================================================
; SECTION 6 — STORE_TIMER_SETTINGS
; Converts selected interval ? tick count
; Saves tick limit + number of intervals into correct timer slot
; ============================================================

STORE_TIMER_SETTINGS:
     ; Load the selected interval (4, 8, 12, or 24) into AL
    MOV AL, SELECTED_INTERVAL
    
    ; --- Convert interval hours ? internal tick limit ---
    ; Each interval corresponds to a number of "ticks"
    ; Your system uses:
    ;   4 hours  ? BL = 10 ticks
    ;   8 hours  ? BL = 20 ticks
    ;   12 hours ? BL = 30 ticks
    ;   24 hours ? BL = 40 ticks
    
    CMP AL, 4            		; Is interval 4 hours?
    JE S10                		 	; If yes ? assign 10 ticks

    CMP AL, 8              		; Is interval 8 hours?
    JE S20

    CMP AL, 12             		; Is interval 12 hours?
    JE S30
    
    ;Otherwise must be 24hrs
    JMP S40

    ; --------- Assign tick limits to BL ---------
    
S10:
MOV BL,10 				; 4 hrs = 10 ticks
JMP SAVE 				; Jump to SAVE Routine

S20: 
MOV BL,20				; 8 hours = 20 ticks
 JMP SAVE
 
S30: 
MOV BL,30				; 12 hours = 30 ticks
JMP SAVE 

S40: 
MOV BL,40				; 24 hours = 40 ticks

; ============================================================
; SAVE tick limit and interval count to correct slot
; ============================================================
SAVE:

    ; TIMER_COUNT indicates which slot (1–5) we are configuring
    MOV AL, TIMER_COUNT
    
    CMP AL,1 
    JE ST1				; Save to Slot 1
    
    CMP AL,2 
    JE ST2				; Save to Slot 2
    
    CMP AL,3 			; Save to Slot 3
    JE ST3
    
    CMP AL,4 			; Save to Slot 4
    JE ST4
    
    CMP AL,5 			; Save to Slot 5
    JE ST5
    
    RET				; Safety Return

 ; ========== SLOT 1 SAVE ROUTINE ==========
ST1:
    MOV T1_Count_Limit, BL         		; Save tick limit into Slot 1
    MOV AL, INTERVAL_COUNT         	; AL = how many total intervals
    MOV T1_Intervals_Count, AL     	; Save how many doses Slot 1 requires
    MOV T1_Count, 0                ;		 Reset current tick counter
    RET
    
; ========== SLOT 2 SAVE ROUTINE ==========
ST2:
    MOV T2_Count_Limit, BL
    MOV AL, INTERVAL_COUNT
    MOV T2_Intervals_Count, AL
    MOV T2_Count, 0
    RET
    
 ; ========== SLOT 3 SAVE ROUTINE ==========
ST3:
 MOV T3_Count_Limit,BL
     MOV AL,INTERVAL_COUNT
     MOV T3_Intervals_Count,AL
     MOV T3_Count,0
     RET
     
; ========== SLOT 4 SAVE ROUTINE ==========     
ST4: 
MOV T4_Count_Limit,BL
     MOV AL,INTERVAL_COUNT
     MOV T4_Intervals_Count,AL
     MOV T4_Count,0
     RET

 ; ========== SLOT 5 SAVE ROUTINE ==========
ST5: 
MOV T5_Count_Limit,BL
     MOV AL,INTERVAL_COUNT
     MOV T5_Intervals_Count,AL
     MOV T5_Count,0
     RET


; ============================================================
; SECTION 7 — TIMER CONFIRMATION SCREEN
; Displays: "Timer set for Slot X!"
; Then asks user to set next timer or start system
; ============================================================
SHOW_TIMER_CONFIRMATION:

    ; Clear LCD before showing confirmation
    CALL CLEAR_LCD


    ; ---- "Timer set for Slot " ----
    MOV AL, 80H
    CALL INST_CTRL
    
    ; Display message: "Timer set for Slot "
    LEA SI, STR_TIMER_SLOT
    CALL DIS_STR

    ; Display the slot number (1–5)
    MOV AL, TIMER_COUNT				; AL = current slot being configured
    ADD AL, '0'							; convert number ? ASCII
    CALL DATA_CTRL

    ; ---- Add exclamation mark ----
    MOV AL, '!'
    CALL DATA_CTRL

    CALL DELAY_1S

   ; If this was slot 5 ? all timers configured ? skip to ALL_TIMERS_SET
    MOV AL, TIMER_COUNT
    CMP AL, 5
    JAE ALL_TIMERS_SET

    ; Otherwise show "Next Timer" / "Save & Start" menu
    CALL SHOW_NEXT_TIMER_OPTION
    RET

; ============================================================
; SHOW MENU: [#] Next Timer or [*] Save & Start
; ============================================================
SHOW_NEXT_TIMER_OPTION:
    CALL CLEAR_LCD
    
    ; Line 1: print "[#] Next Timer"
    MOV AL,80H
    CALL INST_CTRL
    LEA SI,STR_NEXT_TIMER1
    CALL DIS_STR

    ; Line 2: print "[*] Save&Start"
    MOV AL,0C0H
    CALL INST_CTRL
    LEA SI,STR_NEXT_TIMER2
    CALL DIS_STR

 ; --- Wait for user input ---
NX:
    CALL READ_KEY
    
    ; If '#' pressed ? go to next timer slot
    CMP AL,K_HASH 
    JE NEXTT
    
    ; If '*' pressed ? move to countdown timers
    CMP AL,K_STAR 
    JE ALL_TIMERS_SET
    
    ; Ignore any other key
    JMP NX

 ; --- Increment timer slot and return to INTERVAL MENU ---
NEXTT:
    INC TIMER_COUNT
    JMP INTERVAL_MENU


; ============================================================
; SYSTEM_RESET — Reset ALL variables and return to Main Menu
; Called when ALL slots are completed
; ============================================================
SYSTEM_RESET:
    ; Reset currently active timer slot back to Slot 1
    MOV TIMER_COUNT, 1

    ; Reset all "timer expired" flags
    MOV T1_Set, 0
    MOV T2_Set, 0
    MOV T3_Set, 0
    MOV T4_Set, 0
    MOV T5_Set, 0

    ; Reset current tick counters
    MOV T1_Count, 0
    MOV T2_Count, 0
    MOV T3_Count, 0
    MOV T4_Count, 0
    MOV T5_Count, 0

    ; Reset remaining intervals for each slot
    MOV T1_Intervals_Count, 0
    MOV T2_Intervals_Count, 0
    MOV T3_Intervals_Count, 0
    MOV T4_Intervals_Count, 0
    MOV T5_Intervals_Count, 0

    ; Reset interval tick limits
    MOV T1_Count_Limit, 0
    MOV T2_Count_Limit, 0
    MOV T3_Count_Limit, 0
    MOV T4_Count_Limit, 0
    MOV T5_Count_Limit, 0

    ; Clear alarm and button request flags
    MOV Alarm_flag, 0
    MOV DISPENSE_REQUEST, 0

    ; Go back to welcome screen
    JMP START_SCREEN
    
    ; ============================================================
; SYSTEM IS RUNNING (MAIN TIMER LOOP)
; ============================================================
; ============================================================
; ALL_TIMERS_SET — Enter system running state
; Displays "System is running"
; Then starts timer countdown engine
; ============================================================

ALL_TIMERS_SET:

    ; Clear screen
    CALL CLEAR_LCD

    ; Print "System is running"
    MOV AL, 80H
    CALL INST_CTRL
    LEA SI, STR_ALL_TIMERS_SET
    CALL DIS_STR

    
MAIN_LOOP:
      ; Each loop iteration = 100ms (base time tick)
    CALL DELAY_100MS; <<< base time tick

        ; --------------------------
    ; TIMER 1 CHECK
    ; --------------------------

    MOV AL, T1_Intervals_Count     ; How many intervals left for slot 1?
    CMP AL, 0                      		; If zero ? this slot is done
    JE CHK_T2                      		; Skip to slot 2

    INC T1_Count                   		; Add 1 tick to countdown
    MOV AL, T1_Count               	; Load current tick count
    CMP AL, T1_Count_Limit         	; Reached limit?
    JNE CHK_T2                    		; No ? continue checking

    MOV T1_Set, 1                  		; YES ? Slot 1 interval finished
    JMP ALARM_HANDLER              ; Go signal alarm


CHK_T2:
    MOV AL, T2_Intervals_Count
    CMP AL, 0
    JE CHK_T3

    INC T2_Count
    MOV AL, T2_Count
    CMP AL, T2_Count_Limit
    JNE CHK_T3

    MOV T2_Set, 1
    JMP ALARM_HANDLER

    
CHK_T3:
    MOV AL,T3_Intervals_Count
    CMP AL,0
    JE CHK_T4
    INC T3_Count
    MOV AL,T3_Count
    CMP AL,T3_Count_Limit 
    JNE CHK_T4
    MOV T3_Set,1
    JMP ALARM_HANDLER

CHK_T4:
    MOV AL,T4_Intervals_Count
    CMP AL,0 
    JE CHK_T5
    INC T4_Count
    MOV AL,T4_Count
    CMP AL,T4_Count_Limit 
    JNE CHK_T5
    MOV T4_Set,1
    JMP ALARM_HANDLER

CHK_T5:
    MOV AL,T5_Intervals_Count
    CMP AL,0 
    JE MAIN_LOOP 				; No more intervals ? nothing to check
    
    INC T5_Count
    MOV AL,T5_Count
    CMP AL,T5_Count_Limit 
    JNE MAIN_LOOP				; Not yet finished ? go to next tick
    
    MOV T5_Set,1
    JMP ALARM_HANDLER		 ;Alarm for Slot 5

; ============================================================
; ALARM HANDLER — WAIT FOR INTERRUPT REQUEST
; Called when ANY slot timer expires
; ============================================================
ALARM_HANDLER:
    MOV Alarm_flag, 1				;Sets ALARM Active
    MOV DISPENSE_REQUEST, 0      ; clear old presses

    ;Clear Screen for Alarm msg
    CALL CLEAR_LCD
    MOV AL, 80H
    CALL INST_CTRL
    LEA SI, STR_ALARM_MSG
    CALL DIS_STR

    ; turn ON buzzer (PB7)
    MOV DX, PORTB
    MOV AL, 80H
    OUT DX, AL

 ; Wait for the dispense button to be pressed   
WAIT_INTERRUPT:
    CMP DISPENSE_REQUEST, 1 ; 
    JNE WAIT_INTERRUPT		; If not pressed, loop

    ; button pressed ? clear flags
    MOV DISPENSE_REQUEST, 0
    MOV Alarm_flag, 0

    ; turn OFF buzzer
    MOV DX, PORTB
    MOV AL, 00H
    OUT DX, AL

    ; ======================================
; SHOW "Dispensing..." BEFORE MOTOR RUNS
; ======================================
CALL CLEAR_LCD
MOV AL, 80H
CALL INST_CTRL
LEA SI, STR_DISPENSING
CALL DIS_STR

; Now go dispense
JMP DISPENSE_DOSE

; ============================================================
; DISPENSE ROUTINE
; ============================================================
DISPENSE_DOSE:
    CMP T1_Set,1 		; Did slot 1 finish counting?
    JE  M1                 	; Yes ? dispense slot 1
    
    CMP T2_Set,1 		; Did slot 2 finish counting?
    JE M2				; Yes ? dispense slot 2
    
    CMP T3_Set,1 		; Did slot 3 finish counting?
    JE M3				; Yes ? dispense slot 2
    
    CMP T4_Set,1 		; 
    JE M4
    
    CMP T5_Set,1 
    JE M5

    ; ===== Check if ALL intervals are finished =====
    MOV AL, T1_Intervals_Count				; Add remaining intervals of all slots
    ADD AL, T2_Intervals_Count				
    ADD AL, T3_Intervals_Count
    ADD AL, T4_Intervals_Count
    ADD AL, T5_Intervals_Count

    CMP AL, 0								; If sum = 0 ? nothing left
    JE SYSTEM_RESET       					; ALL medicines dispensed ? restart system

    JMP MAIN_LOOP

M1:
    MOV CURRENT_SLOT, 1         			; Remember which slot is dispensing
    MOV AL, 04H                 				; Motor bitmask for slot 1 (PB2)
    MOV T1_Set, 0               				; Clear "ready" flag
    MOV T1_Count, 0             				; Reset timer counter
    DEC T1_Intervals_Count      			; One interval has been used up
    JMP DO_MOTOR               	 			; Run motor

M2:
    MOV CURRENT_SLOT, 2				
    MOV AL,08H						; Motor bitmask for slot 2
    MOV T2_Set,0						
    MOV T2_Count,0
    DEC T2_Intervals_Count
    JMP DO_MOTOR

M3:
    MOV CURRENT_SLOT, 3				
    MOV AL,10H
    MOV T3_Set,0
    MOV T3_Count,0
    DEC T3_Intervals_Count
    JMP DO_MOTOR

M4:
    MOV CURRENT_SLOT, 4
    MOV AL,20H
    MOV T4_Set,0
    MOV T4_Count,0
    DEC T4_Intervals_Count
    JMP DO_MOTOR

M5:
    MOV CURRENT_SLOT, 5
    MOV AL,40H
    MOV T5_Set,0
    MOV T5_Count,0
    DEC T5_Intervals_Count
    ; fall into DO_MOTOR


DO_MOTOR:
    MOV DX,PORTB
    OUT DX,AL					; Turn motor ON using bitmask stored in AL

    CALL DELAY_1S			; Motor runs for 1 second

    MOV DX,PORTB				
    MOV AL,00H
    OUT DX,AL					; Turn motor OFF

  CALL CLEAR_LCD

; ---- Line 1 ----
MOV AL, 80H               ; Line 1 address
CALL INST_CTRL
LEA SI, STR_DOSE_LINE1    ; "Dose Dispensed"
CALL DIS_STR

; ---- Line 2 ----
MOV AL, 0C0H              ; Line 2 address
CALL INST_CTRL
LEA SI, STR_DOSE_LINE2    ; "at Slot "
CALL DIS_STR

; Add Slot Number
MOV AL, CURRENT_SLOT
ADD AL, '0'
CALL DATA_CTRL

; Add exclamation mark
MOV AL, '!'
CALL DATA_CTRL

 CALL DELAY_2SECONDS

    ; =================================================
    ; CHECK IF ALL INTERVALS ARE NOW FINISHED
    ; =================================================
    MOV AL, T1_Intervals_Count
    ADD AL, T2_Intervals_Count
    ADD AL, T3_Intervals_Count
    ADD AL, T4_Intervals_Count
    ADD AL, T5_Intervals_Count
    CMP AL, 0
    CMP AL, 0
    JNE NOT_DONE_ALL

; ============================================
; SHOW "All slots successfully dispensed"
; ============================================
CALL CLEAR_LCD

; Line 1
MOV AL, 80H
CALL INST_CTRL
LEA SI, STR_ALL_DONE1
CALL DIS_STR

; Line 2
MOV AL, 0C0H
CALL INST_CTRL
LEA SI, STR_ALL_DONE2
CALL DIS_STR

; Show for 1 second
CALL DELAY_1S

JMP SYSTEM_RESET      ; go back to start screen

NOT_DONE_ALL:
    JMP MAIN_LOOP

    ; If not finished, go back to main loop
    JMP MAIN_LOOP


; ============================================================
; ISR FOR IR0 — DISPENSE BUTTON INTERRUPT
; ============================================================
ISR_DISPENSE PROC FAR
    PUSH AX			; Save AX
    PUSH DX			; Save DX

    ; ------------------------------
    ; Send End-Of-Interrupt (EOI)
    ; to the 8259 PIC
    ; ------------------------------
    MOV DX, PIC_CMD        ; PIC command port
    MOV AL, 20H            ; EOI command
    OUT DX, AL             ; Notify PIC that interrupt is serviced

    ; ------------------------------
    ; Tell the main loop:
    ; "Button was pressed"
    ; ------------------------------
    MOV DISPENSE_REQUEST, 1
    
    POP DX			; Restore DX
    POP AX			; Restore AX
    
    IRET				; Return from interrupt
    
ISR_DISPENSE ENDP

; ============================================================
; LCD + DELAY + KEYPAD DRIVERS
; (UNCHANGED FROM YOUR CODE)
; ============================================================

; ============================================================
; DISPLAY INTERVAL TEXT
; ============================================================
; gets called from INTERVAL_SELECTED
DISPLAY_INTERVAL_TEXT PROC
    CMP AL, 4
    JE DISP_4
    
    CMP AL, 8
    JE DISP_8
    
    CMP AL, 12
    JE DISP_12
    
    CMP AL, 24
    JE DISP_24
    RET

DISP_4:
    LEA SI, TXT_4H		; Point SI to 4 hrs
    CALL DIS_STR		; Print it
    RET

DISP_8:
    LEA SI, TXT_8H
    CALL DIS_STR
    RET

DISP_12:
    LEA SI, TXT_12H
    CALL DIS_STR
    RET

DISP_24:
    LEA SI, TXT_24H
    CALL DIS_STR
    RET
DISPLAY_INTERVAL_TEXT ENDP ; ENDS PROCEDURE


; KEYPAD 
READ_KEY:
    MOV DX, PORTC		; Keypad Port
    
KWAIT:
    IN AL, DX			; Read Keypad
    TEST AL,10H		
    JZ KWAIT
    
    IN AL, DX                  	; Read again (actual key)
    AND AL, 0FH           	; Mask upper nibble ? only key value
    PUSH AX                	; Save key code
 
KR:
    IN AL,DX			; Read again 
    TEST AL,10H		; Wait until key is released
    JNZ KR
    
    POP AX			; Restore key code
    RET

DIS_STR:
    PUSH SI			; Save SI
    
NXT:
    MOV AL,[SI]		; Load one character
    CMP AL,'$'			; End of string?
    JE DONE
    
    CALL DATA_CTRL	; Print character
    
    INC SI				; Move to next character
    JMP NXT			; Repeat
    
DONE:
    POP SI				; Restore SI
    RET

 ;=========================
; SEND INSTRUCTION TO LCD
; - Uses enable pulse (E) to latch command
;========================= 
INST_CTRL:
    PUSH AX			
    PUSH DX			

    ; Put data on PORTA
    MOV DX, PORTA	; LCD data bus
    OUT DX, AL		; Put AL on data pins

    ; E=1 RS=0 ? 02h
    MOV DX, PORTB
    MOV AL, 02h		; RS=0, E=1
    OUT DX, AL
    NOP
    NOP

    ; E=0 RS=0 ? 00h
    MOV AL, 00h		; RS=0, E = 0
    OUT DX, AL
    CALL DELAY_1MS	; Wait for LCD

    POP DX			; Retrieve DX, AX
    POP AX
    RET

;=========================
; SEND DATA TO LCD
; - Same as INST_CTRL, but RS = 1
;========================= 
DATA_CTRL:
    PUSH AX
    PUSH DX

    MOV DX, PORTA		; LCD data bus
    OUT DX, AL			; Send Data byte

    ; E=1 RS=1 ? 03h
    MOV DX, PORTB			
    MOV AL, 03h			; RS = 1, E = 1
    OUT DX, AL
    NOP
    NOP

    ; E=0 RS=1 ? 01h
    MOV AL, 01h			;RS = 1, E = 0
    OUT DX, AL
    CALL DELAY_1MS

    POP DX
    POP AX
    RET

INIT_LCD:
    MOV AL,38H			; Function set
    CALL INST_CTRL
    
    MOV AL,08H			; Display OFF
    CALL INST_CTRL
    
    MOV AL,01H			; Clear Display
    CALL INST_CTRL
    
    MOV AL,06H			; Entry mode: increment, no shift
    CALL INST_CTRL
    
    MOV AL,0CH			; Display ON, cursor off
    CALL INST_CTRL
    RET


CLEAR_LCD:
    MOV AL,01H
    CALL INST_CTRL		; Clear LCD
    CALL DELAY_1MS
    RET
    
;================================
; DELAY ROUTINES
;================================
;DELAY 1MS
DELAY_1MS:
    PUSH CX
    MOV CX,1000
D1:
    LOOP D1
    POP CX
    RET
 
;DELAY 100,S 
DELAY_100MS:
    PUSH CX
    MOV CX,100
D100:
    CALL DELAY_1MS
    LOOP D100
    POP CX
    RET

 ;DELAY 1S   
DELAY_1S:
    PUSH CX
    MOV CX,10
D1S:
    CALL DELAY_100MS
    LOOP D1S
    POP CX
    RET
    
; DELAY 2S
DELAY_2SECONDS:
    PUSH CX
    MOV CX,20
D2S:
    CALL DELAY_100MS
    LOOP D2S
    POP CX
    RET

CODE ENDS
END START
