# MEDICINE-TIME-PILL-DISPENSER
A medicine time pill dispenser run by an 8086 simulated in Proteus. The project is done by team effort led by Christian Darrell Katigbak along with Carl Janwil Go, and yours truly.
## SCHEMATIC
<p align="center">
  <img width="355" height="370" alt="image" src="https://github.com/user-attachments/assets/c05abd80-8d8b-45b8-884f-c706960333ff"
"/>
</p>

## FEATURES

**TIMER & INTERVAL**

The system has **5 slots for medicine storage** (to be stored manually) ready for dispense for its set timer. There are 4 preset intervals the user can choose from:
- 4 hrs
- 8 hrs
- 12 hrs
- 24 hrs
  
Of course in the simulation it doesn't really count down to the preset time intervals so only 5s, 10s, 15s, and 20s (respectively) are set. Moreover, a number of intervals is also decided by the user, but its only **limited within the day**. Setting up the time interval is done statically, so setting the first interval would set it to the first slot of the system-- next interval would go to the second slot, and so on.

**ALARM SYSTEM**

When the timer counts down to zero, a red LED turns on along with an alarm (a buzzer) that goes off a long beep, and it could only stop once the user presses the dispense button (an interrupt to the CPU).

**DISPENSING MECHANISM**

Once the user presses the dispense button-- one of the 5 motors would turn for a couple of seconds to simulate one of the slots opening and dispense the medicine to the user.

## PROBLEMS/LIMITATIONS
- The startup screen of the LCD is bugged.
- The storing of the medicines is static.
- Dispensing of the medicines is done one motor at a time, so not motors could dispense together.
