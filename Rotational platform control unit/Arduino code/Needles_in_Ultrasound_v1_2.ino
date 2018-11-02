// *****************************************************************
/*
  Needles In Ultrasound

  Firmware for the Arduino-based controller
  for the Needles In Ultasound setup from Nick van de Berg, Delft University of Technology

  by Arjan van Dijke - A.P.vanDijke@tudelft.nl
  and Nick van de Berg - N.J.P.vandeBerg@tudelft.nl
  
  MISIT - www.misit.nl
  BioMechanical Engineering
  Delft University of Technology

  hardware used:
  - Arduino Uno Rev3
    https://store.arduino.cc/arduino-uno-rev3
  - SparkFun Big Easy stepper driver + NEMA17 stepper motor
    https://www.sparkfun.com/products/12859
  - SparkFun Rotary Knob
    https://www.sparkfun.com/products/10982
  - Olimex 16x2 LCD Shield
    https://www.olimex.com/Products/Duino/Shields/SHIELD-LCD16x2/

  software used:
  - Arduino IDE 1.8.5
    https://www.arduino.cc/en/Main/Software
  - Wire library, inluded in Arduino IDE
    https://www.arduino.cc/en/Reference/Wire
  - Olimex LCD16x2 library v1.0
    https://www.olimex.com/Products/Duino/Shields/SHIELD-LCD16x2/open-source-hardware
  - AccelStepper library v1.57.1
    http://www.airspayce.com/mikem/arduino/AccelStepper/

  for the Arduino pinout, see: Arduino pinout NAPUS vx.x.docx
  for the menu structure and flowchart, see: Arduino flowchart and menu structure NAPUS vx.x.vsd
  for the project design agreements, see Design agreements NAPUS -version-.docx
*/

  String firmwareversion = "v1.2";

/*    
  changelog:
    v1.2 - 12 April 2018 - added external (Matlab) control and code cleanup for publication
    v1.1 - 20 April 2017 - fixes to 0-ing position
    v1.0 - 23 March 2017 - initial version

*/
// *****************************************************************



// *****************************************************************
// includes
// *****************************************************************
#include <Wire.h>
#include <LCD16x2.h>
#include <AccelStepper.h>



// *****************************************************************
// defines
// *****************************************************************
#define SERIALBAUDRATE 115200   // serial link (usb) baudrate
#define MANUALMOVESPEED 100     // manual move speed in pulses per second
#define MANUALMOVESPEEDG 56     // manual move speed in 10th of degrees per second (steps*360/640)
#define ROTA 2                  // rotary knob pin A
#define ROTB 3                  // rotary knob pin B
#define PUSHBUTTON 4            // rotary knob push button
#define LEDR 5                  // multicolor LED in rotary knob - red
#define LEDG 6                  // multicolor LED in rotary knob - green
#define LEDB 7                  // multicolor LED in rotary knob - blue
#define MOTORSTEP 8             // the stepper motor step pin
#define MOTORDIR 9              // the stepper motor direction pin
#define MOTOREN 10              // the stepper motor enable pin



// *****************************************************************
// variables
// *****************************************************************

// LCD and buttons
LCD16x2 lcd;                    // the LCD shield
char lcdprintbuffer[17];        // buffer for holding printable chars on lcd (16 chars + trailing 0)
byte lcdbuttons;                // to store button state from lcd
boolean button1 = false;        // to store button states
boolean button2 = false;
boolean button3 = false;
boolean button4 = false;

// stepper motor and driver
AccelStepper stepper(AccelStepper::DRIVER, MOTORSTEP, MOTORDIR);   // BigEasy driver on pin MOTORSTEP and MOTORDIR

// rotary knob
// got this from bildr article: http://bildr.org/2012/08/rotary-encoder-arduino/
volatile int lastEncoded = 0;
volatile long encoderValue = 0;     // position of motor in steps
long previousEncoderValue = 0;
volatile long encoderAngle = 0;     // position in motor in 10th of degrees
long previousEncoderAngle = 0;
int lastMSB = 0;
int lastLSB = 0;

// menu items
byte currentmode = 2;           // to store the menu mode (1=zero position, 2=manual move, 3=speed, 4=speed and position, 5=external)
byte previousmode = 0;          // to remember the previous selected mode
boolean showmenu = true;        // flag to indicate if we want to make new settings in the menu

// serial logging
boolean doseriallogging = true;                     // flag to set if we want serial log events
boolean menueventlogged = false;                    // flag to store if we logged the menu entry event
boolean modeeventlogged = false;                    // flag to store if we logged the mode entry event

// serial input
byte inChar;                    // var to store incoming serial characters
long serialPositionG;           // serial read position setting in deci-degrees
long serialPositionP;           // serial read position setting in pulses
long serialSpeedG;              // serial read speed setting in deci-degrees
long serialSpeedP;              // serial read speed setting in pulses
char serialMode;                // 'U' for undefined, 'M' for movement(pos,speed) or 'V' for movement(speed)
boolean externalmode_exit = false;  // flag to exit run loops with C0


// *****************************************************************
// encoder interrupt handler
// *****************************************************************
void updateEncoder() {
  int MSB = digitalRead(ROTA); // MSB = most significant bit
  int LSB = digitalRead(ROTB); // LSB = least significant bit

  int encoded = (MSB << 1) |LSB; // converting the 2 pin value to single number
  int sum  = (lastEncoded << 2) | encoded; // adding it to the previous encoded value

  if(sum == 0b1101 || sum == 0b0100 || sum == 0b0010 || sum == 0b1011) encoderAngle = encoderAngle + 5;    // increase angle
  if(sum == 0b1110 || sum == 0b0111 || sum == 0b0001 || sum == 0b1000) encoderAngle = encoderAngle - 5;    // decrease angle

  lastEncoded = encoded; //store this value for next time
}



// *****************************************************************************
// LED on-off functions, to avoid confusing non deinverting negative unlogic
// *****************************************************************************
void ledred(byte ledstate) {
  switch (ledstate) {
    case 0:
      digitalWrite(LEDR, HIGH);  // switch off red led with inverted logic
      break;
    case 1:
      digitalWrite(LEDR, LOW);   // switch on red led with inverted logic
      break;
    default:
      break;
  }
}

void ledgreen(byte ledstate) {
  switch (ledstate) {
    case 0:
      digitalWrite(LEDG, HIGH);  // switch off green led with inverted logic
      break;
    case 1:
      digitalWrite(LEDG, LOW);   // switch on green led with inverted logic
      break;
    default:
      break;
  }
}

void ledblue(byte ledstate) {
  switch (ledstate) {
    case 0:
      digitalWrite(LEDB, HIGH);  // swtich off blue led with inverted logic
      break;
    case 1:
      digitalWrite(LEDB, LOW);   // switch on blue led with inverted logic
      break;
    default:
      break;
  }
}



// *****************************************************************************
// seriallog: serial prints event ids, milliseconds, and human readable string
// *****************************************************************************

// prototype the function to allow optional arguments
void seriallog (byte eventid, long extradata1 = 0, long extradata2 = 0);

// define the function
void seriallog (byte eventid, long extradata1 = 0, long extradata2 = 0) {

  if (doseriallogging) {
    Serial.print(eventid);                            // print event id
    Serial.print(",");
    Serial.print(millis());                           // print current millis()
    Serial.print(",");
    switch (eventid) {                                // print human readable string
      case 100: Serial.println("NAPUS power on"); break;
      case 101: Serial.println("motor on"); break;
      case 102: Serial.println("motor off"); break;
      case 103: Serial.println("motor stop requested"); break;
      case 104: Serial.println("stepper disabled"); break;
      case 120: Serial.println("serial synced"); break;
      case 150: Serial.println("main menu"); break;
      case 151: Serial.println("zero position mode"); break;
      case 152: Serial.println("position mode"); break;
      case 153: Serial.println("speed mode"); break;
      case 154: Serial.println("speed and position mode"); break;
      case 155: Serial.println("external mode"); break;
      case 161: Serial.println("move to 0"); break;
      case 162: Serial.println("make current position new 0"); break;
      case 171:
        Serial.print("position set to,");
        Serial.print(extradata1);                     // position in 10ths of degrees
        Serial.print(",");
        Serial.println(extradata2);                   // position in steps
        break;
      case 172:
        Serial.print("speed set to,");
        Serial.print(extradata1);                     // speed in in 10ths of degrees per second
        Serial.print(",");
        Serial.println(extradata2);                   // speed in steps per second
        break;
      case 901: Serial.println("impossible mode"); break;
      default: Serial.println("unknown event");
    } // end switch
  } // end if doseriallogging
}




// *****************************************************************
// setup
//   "He who fails to prepare, prepares to fail." (Confucius)
// *****************************************************************
void setup() {

  // setup Serial link
  Serial.begin(SERIALBAUDRATE);

  // setup I2C
  Wire.begin();

  // setup LCD
  lcd.lcdClear();                                     // clear screen
  lcd.lcdSetBlacklight(80);                           // LCD backlight on
  
  // show name and version on lcd
  lcd.lcdGoToXY(1,1);                                 // line 1 position 1
  //            0123456789012345
  lcd.lcdWrite(" Needles-in-US");
  lcd.lcdGoToXY(7,2);                                 // line 2 position 7
  firmwareversion.toCharArray(lcdprintbuffer,16);     // put versionstring in lcdprintbuffer
  lcd.lcdWrite(lcdprintbuffer);                       // and print it on LCD
  delay(3000);
  lcd.lcdClear();                                     // clear LCD

  // rotary knob
  pinMode(ROTA, INPUT_PULLUP); 
  pinMode(ROTB, INPUT_PULLUP);
  pinMode(PUSHBUTTON, INPUT);                         // INPUT, because it has its own (hardware) pulldown
  attachInterrupt(0, updateEncoder, CHANGE);          // attach interrupt to ROTA, call handler on change of the signal
  attachInterrupt(1, updateEncoder, CHANGE);          // attach interrupt to ROTB, call handler on change of the signal

   // LEDs
  pinMode(LEDR, OUTPUT);
  ledred(0);                                          // red led OFF at startup
  pinMode(LEDG, OUTPUT);
  ledgreen(0);                                        // green led OFF at startup
  pinMode(LEDB, OUTPUT);
  ledblue(1);                                         // blue led ON at startup

  // stepper
  stepper.setPinsInverted(false,false,true);          // direction normal, step normal, enable inverted
  stepper.setEnablePin(MOTOREN);                      // set motor enable pin
  stepper.setMaxSpeed(1000);                          // max speed of the stepper
  stepper.setAcceleration(100);                       // max acceleration of the stepper
  stepper.disableOutputs();                           // disable stepper at startup (!)

  // log event
  seriallog(100);                                     // event 100: NAPUS power on

}



// *****************************************************************
// loop
//   "Who runs in circles never gets far." (Thornton Burgess)
// *****************************************************************
void loop() {

  // local variables
  char printBuffer[8];     // used for printing angle on LCD
  int encoderAngle1 = 0;   // used for printing angle on LCD
  int encoderAngle2 = 0;   // used for printing angle on LCD



  // read buttons and update booleans
  lcdbuttons = lcd.readButtons();
  if(!(lcdbuttons & 0x01)) button1=true; else button1=false;
  if(!(lcdbuttons & 0x02)) button2=true; else button2=false;
  if(!(lcdbuttons & 0x04)) button3=true; else button3=false;
  if(!(lcdbuttons & 0x08)) button4=true; else button4=false;


  
  
  // ***********************
  // ** main menu
  // ***********************
  // if showmenu is true (and the first time we enter loop() this is the case) , we want to make new settings in the menu
  if (showmenu) {

    // log events, only once
    if (!menueventlogged) {
      stepper.disableOutputs();                         // disable stepper
      seriallog(104);                                   // event 104: stepper disabled
      menueventlogged = true;
      seriallog(150);                                 // event 150: main menu
    }

    if (currentmode != previousmode) {
      // we selected a new mode
      previousmode = currentmode;
      // rewrite 1st line
      lcd.lcdGoToXY(1,1);                             // line 1 position 1
      lcd.lcdWrite("                ");               // 16 spaces
      lcd.lcdGoToXY(1,1);                             // line 1 position 1
      //                                       0123456789012345
      if (currentmode == 1)      lcd.lcdWrite("1.Zero Position");
      else if (currentmode == 2) lcd.lcdWrite("2.Position Mode");
      else if (currentmode == 3) lcd.lcdWrite("3.Speed Mode");
      else if (currentmode == 4) lcd.lcdWrite("4.Speed/Pos Mode");
      else if (currentmode == 5) lcd.lcdWrite("5.External Mode");
      else lcd.lcdWrite("Impossible Mode");

      // 2nd line
      lcd.lcdGoToXY(1,2);                             // line 2 position 1
      //            1234567890123456
      lcd.lcdWrite("<-     ok     ->");
    }

    // handle buttons
    if (button1) {
      while (!(lcdbuttons & 0x01)) {
        lcdbuttons = lcd.readButtons();               // wait for button release
      }
      currentmode--;                                  // decrease mode
      if (currentmode<1) currentmode=5;
    }
    if (button2) {
      while (!(lcdbuttons & 0x02)) {
        lcdbuttons = lcd.readButtons();               // wait for button release
      }
      modeeventlogged = false;                        // mode sure the following mode entry is logged
      showmenu = false;                               // exit menu
    }
    if (button3) {
      while (!(lcdbuttons & 0x04)) {
        lcdbuttons = lcd.readButtons();               // wait for button release
      }
      modeeventlogged = false;                        // mode sure the following mode entry is logged
      showmenu = false;                               // exit menu
    }
    if (button4) {
      while (!(lcdbuttons & 0x08)) {
        lcdbuttons = lcd.readButtons();               // wait for button release
      }
      currentmode++;                                  // increase mode
      if (currentmode>5) currentmode=1;
    }
    
  } // end if showmenu



  else if (currentmode == 1) {
    // *****************************************************************************************************************
    // *****************************************************************************************************************
    // 1. zero position mode
    // *****************************************************************************************************************
    // *****************************************************************************************************************

    // log event
    if (!modeeventlogged) {
      modeeventlogged = true;
      seriallog(151);                                 // event 151: zero position mode
    }

    // build up lcd structure
    lcd.lcdClear();                                   // clear screen
    lcd.lcdGoToXY(1,2);                               // line 2 position 1
    //            1234567890123456
    lcd.lcdWrite("menu        set0");

    // main submenu loop
    while (true) {

      // read buttons
      lcdbuttons = lcd.readButtons();
      if(!(lcdbuttons & 0x01)) button1=true; else button1=false;
      if(!(lcdbuttons & 0x02)) button2=true; else button2=false;
      if(!(lcdbuttons & 0x04)) button3=true; else button3=false;
      if(!(lcdbuttons & 0x08)) button4=true; else button4=false;

      // button1: go to menu next loop
      if (button1) {
        // wait for button release
        while (!(lcdbuttons & 0x01)) {
          lcdbuttons = lcd.readButtons();
        }
        button1 = false;
        lcd.lcdClear();                               // clear screen
        previousmode = 0;                             // make previousmode invalid to force menu rewrite
        menueventlogged = false;                      // make sure the following menu entering is logged
        showmenu = true;
        break;                                        // exit while true loop
      } // end if button1



      // button4: make this position zero
      if (button4) {
        // wait for button release
        while (!(lcdbuttons & 0x08)) {
          lcdbuttons = lcd.readButtons();
        }
        button4 = false;

        // log event
        seriallog(162);                               // event 162: make current position new 0

        // do it
        stepper.setCurrentPosition(0);                // make current position the new 0-point

        // confirm it on lcd
        lcd.lcdGoToXY(14,1);                          // line 1 position 14
        lcd.lcdWrite("Ok");
        delay(1000);
        lcd.lcdGoToXY(14,1);                          // line 1 position 14
        lcd.lcdWrite("  ");
        
      } // end if button4
    
    } // end while true main submenu loop

    // exit to menu
    menueventlogged = false;                          // make sure the following menu entering is logged
    previousmode = 0;                                 // make sure menu is shown
    showmenu = true;
  }




  else if (currentmode == 2) {
    // *****************************************************************************************************************
    // *****************************************************************************************************************
    // 2. position mode
    // *****************************************************************************************************************
    // *****************************************************************************************************************

    // log event
    if (!modeeventlogged) {
      modeeventlogged = true;
      seriallog(152);                                 // event 152: position mode
    }

    // enable stepper
    stepper.enableOutputs();


    // build up lcd structure
    lcd.lcdClear();                                   // clear screen
    lcd.lcdGoToXY(1,1);                               // line 1 position 1
    lcd.lcdWrite("Go To:");
    lcd.lcdGoToXY(8,1);                               // line 1 position 8
    encoderAngle1 = encoderAngle/10;
    encoderAngle2 = encoderAngle%10;
    sprintf(printBuffer, "%d.%d d", encoderAngle1, encoderAngle2);
    lcd.lcdWrite(printBuffer);
    lcd.lcdGoToXY(1,2);                               // line 2 position 1
    //            1234567890123456
    lcd.lcdWrite("menu  -  +  move");

    // main submenu loop
    while (true) {

      // update lcd
      if (encoderAngle != previousEncoderAngle) {
        // we need to update the value on the lcd
        lcd.lcdGoToXY(8,1);                           // line 1 position 8
        lcd.lcdWrite("         ");                    // 9 spaces
        lcd.lcdGoToXY(8,1);                           // line 1 position 8
        encoderAngle1 = encoderAngle/10;
        encoderAngle2 = encoderAngle%10;
        sprintf(printBuffer, "%d.%d d", encoderAngle1, encoderAngle2);
        lcd.lcdWrite(printBuffer);
        previousEncoderAngle = encoderAngle;          // store encoder angle for next loop
      }
 
      // handle pushbutton
      if (digitalRead(PUSHBUTTON) == true) {
        // small delay and read again
        delay(50);
        if (digitalRead(PUSHBUTTON) == true) {
          // zero encoderValue
          encoderAngle = 0;
        }
      }

      // handle buttons
      lcdbuttons = lcd.readButtons();
      if(!(lcdbuttons & 0x01)) button1=true; else button1=false;
      if(!(lcdbuttons & 0x02)) button2=true; else button2=false;
      if(!(lcdbuttons & 0x04)) button3=true; else button3=false;
      if(!(lcdbuttons & 0x08)) button4=true; else button4=false;

      // button1: go into menu next loop
      if (button1) {
        // wait for button release
        while (!(lcdbuttons & 0x01)) {
          lcdbuttons = lcd.readButtons();
        }
        button1 = false;
        lcd.lcdClear();                               // clear screen
        previousmode = 0;                             // make previousmode invalid to force menu rewrite
        menueventlogged = false;                      // make sure the following menu entering is logged
        showmenu = true;
        break;                                        // exit while loop
      } // end if button1

      // button2: decrease encoderAngle with 1 (-0.1 degree)
      if (button2) {
        // wait for button release
        while (!(lcdbuttons & 0x02)) {
          lcdbuttons = lcd.readButtons();
        }
        button2 = false;                              // prevent push and hold on button
        encoderAngle = encoderAngle - 1;
      }

      // button3: increase encoderAngle with 1 (+0.1 degree)
      if (button3) {
        // wait for button release
        while (!(lcdbuttons & 0x04)) {
          lcdbuttons = lcd.readButtons();
        }
        button3 = false;                              // prevent push and hold
        encoderAngle = encoderAngle + 1;
      }

      // button4: execute movement
      if (button4) {

        // wait for button release
        delay(500);
        while (!(lcdbuttons & 0x08)) {
          lcdbuttons = lcd.readButtons();
        }

        // calculate steps from angle
        encoderValue = (encoderAngle * 640) / 360;                       // 360 degrees is 6400 steps, so: steps = (10ths_degrees * 640) / 360

        // log event
        //  360 degrees is 6400 steps, so 10th_degrees =  steps*360/640
        seriallog(171, encoderAngle, encoderValue);                     // event 171: position set to [pos_10thdegrees], [pos_steps]
        seriallog(172, MANUALMOVESPEEDG, MANUALMOVESPEED);              // event 172, speed set to [speed_10thdegrees], [speed_steps]

        // change display
        lcd.lcdGoToXY(13,2);                          // line 2 position 13
        lcd.lcdWrite("    ");                         // 4 spaces
        lcd.lcdGoToXY(13,2);                          // line 2 position 13
        lcd.lcdWrite("stop");

        // change leds
        ledblue(0);
        ledred(1);
        
        // move that motor
        stepper.moveTo(encoderValue);
        if (stepper.currentPosition() < encoderValue) {
          stepper.setSpeed(MANUALMOVESPEED);          // move forward
        }
        else
          stepper.setSpeed(-MANUALMOVESPEED);         // move backward

        // log event
        seriallog(101);                               // event 101: motor on


        // loop until motor has reached setpoint position
        while (stepper.currentPosition() != encoderValue) {

          // run motor, run!
          stepper.runSpeed();

          // handle buttons
          lcdbuttons = lcd.readButtons();
          if(!(lcdbuttons & 0x01)) button1=true; else button1=false;
          if(!(lcdbuttons & 0x08)) button4=true; else button4=false;

          // button1: stop motor and go to menu
          if (button1) {

            // wait for button release
            while (!(lcdbuttons & 0x01)) {
              lcdbuttons = lcd.readButtons();
            }

            // log event
            seriallog(103);                           // event 103: motor stop requested

            // stop the stepper and break out of while loop
            stepper.stop();
            break;
          }

          // button4: stop motor and stay in manual move loop
          if (button4) {

            // wait for button release
            while (!(lcdbuttons & 0x08)) {
              lcdbuttons = lcd.readButtons();
            }

            // log event
            seriallog(103);                           // event 103: motor stop requested


            // stop the stepper and break out of while loop
            button4 = false;                          // button4 reset to keep us in this menu item
            stepper.stop();
            break;
          }

        } // end while stepper


        // log event
        seriallog(102);                               // event 102: motor off

        // change leds
        ledred(0);
        ledblue(1);

        // change display
        lcd.lcdGoToXY(13,2);                          // line 2 position 13
        lcd.lcdWrite("    ");                         // 4 spaces
        lcd.lcdGoToXY(13,2);                          // line 2 position 13
        lcd.lcdWrite("move");

      } // end if button4


      // button 1 will exit to menu
      if (button1) {
        menueventlogged = false;                      // make sure the following menu entering is logged
        previousmode = 0;                             // make sure menu is shown
        showmenu = true;                              // get us in the menu
        break;                                        // break out of while loop
      }
    } // end while true

  } // end if manual move mode




  else if (currentmode == 3) {
    // *****************************************************************************************************************
    // *****************************************************************************************************************
    // 3. speed mode
    // *****************************************************************************************************************
    // *****************************************************************************************************************

    // log event
    if (!modeeventlogged) {
      modeeventlogged = true;
      seriallog(153);                                 // event 153: speed mode
    }

    // enable stepper
    stepper.enableOutputs();

    // set encoderValue to 0 to allow speed setting
    // TODO?: save value in other var for later use?
    encoderValue = 0;

    // build up lcd structure
    lcd.lcdClear();                                   // clear screen
    lcd.lcdGoToXY(1,1);                               // line 1 position 1
    lcd.lcdWrite("Speed");
    lcd.lcdGoToXY(8,1);                               // line 1 position 8
    lcd.lcdWrite("0");
    lcd.lcdGoToXY(1,2);                               // line 2 position 1
    //            1234567890123456
    lcd.lcdWrite("menu  -  +  move");

    // submenu loop
    while (true) {
      // main speed mode loop

      // update lcd
      if (encoderValue != previousEncoderValue) {
        // we need to update the value on the lcd
        lcd.lcdGoToXY(8,1);                           // line 1 position 8
        lcd.lcdWrite("         ");                    // 9 spaces
        lcd.lcdGoToXY(8,1);                           // line 1 position 8
        lcd.lcdWrite(encoderValue);                   // new encoder value
        previousEncoderValue = encoderValue;          // store encoder value for next loop
      }
 
      // handle pushbutton
      if (digitalRead(PUSHBUTTON) == true) {
        // small delay and read again
        delay(50);
        if (digitalRead(PUSHBUTTON) == true) {
          // zero encoderValue
          encoderValue = 0;
        }
      }

      // handle buttons
      lcdbuttons = lcd.readButtons();
      if(!(lcdbuttons & 0x01)) button1=true; else button1=false;
      if(!(lcdbuttons & 0x02)) button2=true; else button2=false;
      if(!(lcdbuttons & 0x04)) button3=true; else button3=false;
      if(!(lcdbuttons & 0x08)) button4=true; else button4=false;

      // button1: go into menu next loop
      if (button1) {
        // wait for button release
        while (!(lcdbuttons & 0x01)) {
          lcdbuttons = lcd.readButtons();
        }
        button1 = false;
        lcd.lcdClear();                               // clear screen
        previousmode = 0;                             // make previousmode invalid to force menu rewrite
        menueventlogged = false;                      // make sure the following menu entering is logged
        showmenu = true;
        break;                                        // exit while loop
      } // end if button1

      // button2: decrease encoderValue
      if (button2) {
        // wait for button release
        while (!(lcdbuttons & 0x02)) {
          lcdbuttons = lcd.readButtons();
        }
        button2 = false;                              // prevent push and hold of button
        encoderValue = encoderValue - 10;
      }

      // button3: increase encoderValue
      if (button3) {
        // wait for button release
        while (!(lcdbuttons & 0x04)) {
          lcdbuttons = lcd.readButtons();
        }
        button3 = false;                              // prevent push and hold of button
        encoderValue = encoderValue + 10;
      }

      // button4: execute movement
      if (button4) {

        // wait for button release
        delay(500);
        while (!(lcdbuttons & 0x08)) {
          lcdbuttons = lcd.readButtons();
        }

        // log event
        //  360 degrees is 6400 steps, so 10th_degrees =  steps*360/640
        seriallog(172, (MANUALMOVESPEED*360)/640, MANUALMOVESPEED);          // event 172, speed set to [speed_10thdegrees], [speed_steps]

        // change display
        lcd.lcdGoToXY(13,2);                          // line 2 position 13
        lcd.lcdWrite("    ");                         // 4 spaces
        lcd.lcdGoToXY(13,2);                          // line 2 position 13
        lcd.lcdWrite("stop");

        // change leds
        ledblue(0);
        ledred(1);
        
        // move the motor
        stepper.setSpeed(encoderValue);

        // log event
        if (seriallog) {
          Serial.print("101,");                       // event id
          Serial.print(millis());                     // print current millis()
          Serial.print(",");
          Serial.println("motor on");                 // print human readable log entry
        }

        // runSpeed loop, escape with button1 or button4
        while (true) {

          // run motor, run!
          stepper.runSpeed();

          // handle buttons
          lcdbuttons = lcd.readButtons();
          if(!(lcdbuttons & 0x01)) button1=true; else button1=false;
          if(!(lcdbuttons & 0x08)) button4=true; else button4=false;

          // button1: stop motor and go to menu
          if (button1) {
            // wait for button release
            while (!(lcdbuttons & 0x01)) {
              lcdbuttons = lcd.readButtons();
            }

            // log event
            seriallog(103);                           // event 103: motor stop requested

            // stop stepper and break out of stepper loop
            stepper.stop();
            break;
          }

          // button4: stop motor and stay in manual move loop
          if (button4) {
            // wait for button release
            while (!(lcdbuttons & 0x08)) {
              lcdbuttons = lcd.readButtons();
            }

            // log event
            seriallog(103);                           // event 103: motor stop requested

            // stop stepper and break out of stepper loop
            button4 = false;                          // button4 reset to keep us in this menu item
            stepper.stop();
            break;
          }

        } // end while stepper

        // log event
        seriallog(102);                               // event 102: motor off

        // change leds
        ledred(0);
        ledblue(1);

        // change display
        lcd.lcdGoToXY(13,2);                          // line 2 position 13
        lcd.lcdWrite("    ");                         // 4 spaces
        lcd.lcdGoToXY(13,2);                          // line 2 position 13
        lcd.lcdWrite("move");

      } // end if button4

      // button1 will exit to menu
      if (button1) {
        menueventlogged = false;                      // make sure the following menu entering is logged
        previousmode = 0;                             // make sure menu is shown
        showmenu = true;                              // get us in the menu
        break;                                        // break out of while loop
      }
    } // end while true

  } // end if speed mode




  else if (currentmode == 4) {
    // *****************************************************************************************************************
    // *****************************************************************************************************************
    // 4. speed and position mode (NOT IMPLEMENTED YET in v1.2)
    // *****************************************************************************************************************
    // *****************************************************************************************************************

    // log event
    if (!modeeventlogged) {
      modeeventlogged = true;
      seriallog(154);                                 // event 154: speed and position mode
    }

    delay(1000);

    // exit to menu
    menueventlogged = false;                          // make sure the following menu entering is logged
    showmenu = true;

  } // end if speed and position mode





  else if (currentmode == 5) {
    // *****************************************************************************************************************
    // *****************************************************************************************************************
    // 5. external mode
    // *****************************************************************************************************************
    // *****************************************************************************************************************

    // switch off LEDs in rotary knob
    ledred(0);
    ledgreen(0);
    ledblue(0);

    // set serial mode to 'U' from undefined
    serialMode = 'U';

    // log event
    if (!modeeventlogged) {
      modeeventlogged = true;
      seriallog(155);                                 // event 155: external mode
    }


    /*
      serial incoming commands:
      ! - sync byte from serial link
      Mx,v   - move (to_this_pos_x[10th_degrees], with_this_speed_v[10th_degrees/second])
      Vv - move (inf, with_this_speed_v[10th_degrees/second])
      C0 - control(stop): stop movement
      C1 - control(start): start movement
      C5 - control(zero): set this position as the new 0-position
      C9 - control(release): disable stepper to move motor around freely

      make sure to send a newline ('\n') after the command
    */


    // wait for handshake character ('!') from serial link
    lcd.lcdClear();                                   // clear screen
    lcd.lcdGoToXY(1,1);                               // line 1 position 1
    //            1234567890123456
    lcd.lcdWrite("Waiting for");
    lcd.lcdGoToXY(1,2);                               // line 2 position 1
    lcd.lcdWrite(" serial sync...");

    // loop until sync character is read
    while (true) {
      if (Serial.available() > 0) {
        inChar = Serial.read();
        if (inChar == '!') break;
      }
      delay(100);                                     // slow down a bit
    }

    // clean read buffer
    while (Serial.available() > 0) {
        inChar = Serial.read();
    }

    // tell user and log we are synced
    lcd.lcdClear();                                   // clear screen
    lcd.lcdGoToXY(1,1);                               // line 1 position 1
    //            1234567890123456
    lcd.lcdWrite("Yes, we synced!");
    seriallog(120);                                   // event 120: serial synced
    delay(2000);

    // build up basic lcd structure
    lcd.lcdClear();                                   // clear screen
    lcd.lcdGoToXY(1,1);                               // line 1 position 1
    //            1234567890123456
    lcd.lcdWrite("Po:0000  Sp:0000");
    lcd.lcdGoToXY(1,2);                               // line 2 position 1
    lcd.lcdWrite("menu");

    
    // main external mode loop
    while (true) {

      // handle buttons
      lcdbuttons = lcd.readButtons();
      if(!(lcdbuttons & 0x01)) button1=true; else button1=false;

      // button1: go into menu next loop
      if (button1) {

        // wait for button release
        while (!(lcdbuttons & 0x01)) {
          lcdbuttons = lcd.readButtons();
        }

        // log event
        seriallog(103);                               // event 103: motor stop requested

        // stop and exit
        stepper.stop();                               // stop the stepper
        seriallog(102);                               // event 102: motor stop
        button1 = false;
        lcd.lcdClear();                               // clear screen
        previousmode = 0;                             // make previousmode invalid to force menu rewrite
        menueventlogged = false;                      // make sure the following menu entering is logged
        showmenu = true;
        break;                                        // exit main while loop
      } // end if button1



      // check for serial commands
      if (Serial.available() > 0) {

        inChar = Serial.read();

        // move command 'M'
        if (inChar == 'M') {

          // set movement mode to 'M'
          serialMode = inChar;

          // read position and speed and recalculate
          serialPositionG = Serial.parseInt();
          serialPositionP = (serialPositionG * 640) / 360;        // 360 degrees is 6400 steps, so: steps = (10ths_degrees * 640) / 360
          serialSpeedG = Serial.parseInt();
          serialSpeedP = (serialSpeedG * 640) / 360;              // 360 degrees is 6400 steps, so: steps = (10ths_degrees * 640) / 360
          lcd.lcdGoToXY(4,1); lcd.lcdWrite("      ");
          lcd.lcdGoToXY(4,1); lcd.lcdWrite(serialPositionG);
          lcd.lcdGoToXY(13,1); lcd.lcdWrite("    ");
          lcd.lcdGoToXY(13,1); lcd.lcdWrite(serialSpeedG);

          // log events
          seriallog(171, serialPositionG, serialPositionP);       // event 171: position set to [pos_10thdegrees], [pos_steps]
          seriallog(172, serialSpeedG, serialSpeedP);             // event 172, speed set to [speed_10thdegrees], [speed_steps]

        } // end if inChar == 'M'


        // velocity command 'V'
        else if (inChar == 'V') {

          // set movement mode to 'V'
          serialMode = inChar;
                    
          // read speed
          serialSpeedG = Serial.parseInt();
          serialSpeedP = (serialSpeedG * 640) / 480;
          lcd.lcdGoToXY(4,1); lcd.lcdWrite("inf   ");
          lcd.lcdGoToXY(13,1); lcd.lcdWrite("    ");
          lcd.lcdGoToXY(13,1); lcd.lcdWrite(serialSpeedG);

          // log event
          seriallog(172, serialSpeedG, serialSpeedP);             // event 172, speed set to [speed_10thdegrees], [speed_steps]
       
        } // end if inchar == 'V'


        else if (inChar == 'C') {
          // control command
          inChar = Serial.read();

          // C0: stop movement and release
          if (inChar == '0') {

            // log event
            seriallog(103);                           // event 103, motor stop requested

            // stop the stepper
            stepper.stop();

            // log event
            seriallog(102);                           // event 102, motor off 

            // change LCD
            lcd.lcdGoToXY(1,2);                       // line 2 position 1
            //            1234567890123456
            lcd.lcdWrite("menu            ");


          } // end if inChar == '0' or '9'

          
          // C1: start movement
          else if (inChar == '1' && serialSpeedG != 0) {

            // change LCD
            lcd.lcdGoToXY(1,2);                       // line 2 position 1
            //            1234567890123456
            lcd.lcdWrite("            stop");

            // enable stepper
            stepper.enableOutputs();


            // check if we have a position task (move to position with certain speed)
            if (serialMode == 'M') {

              // move that motor
              stepper.moveTo(encoderValue);
              if (stepper.currentPosition() < serialPositionP) {
                stepper.setSpeed(serialSpeedP);       // move forward
              }
              else {
                stepper.setSpeed(-serialSpeedP);      // move backward
              }
  
              // log event
              seriallog(101);                         // event 101: motor on
          
              while (stepper.currentPosition() != serialPositionP) {

                // run motor, run!
                stepper.runSpeed();
  
                // check for 'C0' on serial and set flag to exit if found
                externalmode_exit = false;
                if (Serial.available() > 0) {
                  inChar = Serial.read();
                  if (inChar == 'C') {
                    // control command
                    inChar = Serial.read();
                    if (inChar == '0') {
                      // C0 received: set flag to exit (handled in button4 handler)
                      externalmode_exit = true;
                    }
                  }
                }
                
                // handle buttons
                lcdbuttons = lcd.readButtons();
                if(!(lcdbuttons & 0x08)) button4=true; else button4=false;

                if (button4 || externalmode_exit) {
                  // button4 or C0 received : stop motor
                  while (!(lcdbuttons & 0x08)) {      // wait for button release
                    lcdbuttons = lcd.readButtons();
                  }
  
                  // log event
                  seriallog(103);                     // event 103: motor stop requested
  
                  // stop motor and exit loop
                  button4 = false;                    // button4 reset to keep us in this menu item
                  stepper.stop();                     // stop the stepper
                  break;                              // break out of while stepper loop
                } // end if button4
  
              } // end while stepper
  
              // log event
              seriallog(102);                         // event 102: motor off
  
              // change LCD
              lcd.lcdGoToXY(1,2);                     // line 2 position 1
              //            1234567890123456
              lcd.lcdWrite("menu            ");
  
            } // end if serialMode == 'M'


            // check if we have a velocity task (move with certain speed)
            else if (serialMode == 'V') {

              //set the motor speed
              stepper.setSpeed(serialSpeedP);
  
              // log event
              seriallog(101);                         // event 101: motor on
          
              while (true) {                          // runSpeed loop, escape with button1 or button4
  
                // run motor, run!
                stepper.runSpeed();

                // check for 'C0' on serial and set flag to exit if found
                externalmode_exit = false;
                if (Serial.available() > 0) {
                  inChar = Serial.read();
                  if (inChar == 'C') {
                    // control command
                    inChar = Serial.read();
                    if (inChar == '0') {
                      // C0 received: set flag to exit (handled in button4 handler)
                      externalmode_exit = true;
                    }
                  }
                }

                // handle buttons
                lcdbuttons = lcd.readButtons();
                if(!(lcdbuttons & 0x08)) button4=true; else button4=false;
      
                if (button4 || externalmode_exit) {
                  // button4: stop motor
                  while (!(lcdbuttons & 0x08)) {      // wait for button release
                    lcdbuttons = lcd.readButtons();
                  }
      
                  // log event
                  seriallog(103);                     // event 103: motor stop requested
      
                  // stop motor and exit loop
                  button4 = false;                    // button4 reset to keep us in this menu item
                  stepper.stop();                     // stop the stepper
                  break;                              // break out of while stepper loop
                } // end if button4
  
              } // end while stepper

            } // end if serialMode == 'V'
  
          } // end if inChar == '1'


          // C5: make current position the new 0-position
          else if (inChar == '5') {
            seriallog(162);                           // event 162: make current position new 0
            stepper.setCurrentPosition(0);            // make current position the new 0-point
          }

          // C9: disable stepper (to move motor around freely)
          else if (inChar == '9') {
            seriallog(104);                           // event 104: stepper disabled
          }

        } // end if inChar=='C'
            
      } // end if serial available

    } // end while true

    // exit to menu
    menueventlogged = false;                          // make sure the following menu entering is logged
    showmenu = true;
  }

  else {
    // impossible mode

    // log event
    if (!modeeventlogged) {
      modeeventlogged = true;
      seriallog(901);                                 // event 901: impossible mode
    }

    // exit to menu
    menueventlogged = false;                          // make sure the following menu entering is logged
    showmenu = true;
  }


} // end loop()
