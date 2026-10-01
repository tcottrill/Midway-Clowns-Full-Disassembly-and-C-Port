;Clowns (Midway, 1978) - annotated disassembly of the program ROM $0000-$17FF.
;MAME set 'clowns' (rev. 2): h2.cpu g2.cpu f2.cpu e2.cpu d2.cpu c2.cpu, 1K each.
;Intel 8080 on the Midway 8080 black & white board: 256 x 224 bitmap at $2400,
;MB14241 shifter on ports 1-3, tone generator and discrete sounds on ports 5-7.
;No source for this game is known; every name, routine header and comment was
;written for this disassembly from reading the code.  The hardware notes follow
;the MAME driver (mw8080bw.cpp).
;Every line below was re-encoded and byte-compared with the ROM (verify.py).
;Syntax: Intel 8080 mnemonics; directives as the Tempest / Space Duel listings
;(.org, .include, .alias, .byte, .word); $ is hex, < and > take the low and
;high byte, [ ] groups an expression.  Every code and data line starts with its
;address label Lxxxx; named labels sit on their own line above it.

.org $0000

.include "clowns_defines.asm"


;==============================================================================
; SECTION 1  Reset and interrupt entries, self test ($0000-$0137)
;   The reset and the two RST interrupt entries, then the RAM and ROM tests that
;   run instead of the game while the self-test switch (INP_DIP b7) is on.
;==============================================================================

;------------------------------------------------------------------------------
; Reset - Power-on / watchdog reset entry.
;------------------------------------------------------------------------------
Reset:
L0000:  NOP
L0001:  NOP
L0002:  LXI  SP,$2400               ;Stack at the top of work RAM
L0005:  JMP  Boot                   ;Self-test switch decides: game or RAM/ROM test

;------------------------------------------------------------------------------
; Rst1 - RST 1: mid-screen interrupt (vector $CF).
;   Saves all registers; Rst1Handler leaves through IrqExit.
;------------------------------------------------------------------------------
Rst1:
L0008:  PUSH PSW
L0009:  PUSH B
L000A:  PUSH D
L000B:  PUSH H
L000C:  JMP  Rst1Handler            ;Mid-screen work
L000F:  .byte $00                   ;unused

;------------------------------------------------------------------------------
; Rst2 - RST 2: vertical blank interrupt (vector $D7).
;------------------------------------------------------------------------------
Rst2:
L0010:  PUSH PSW
L0011:  PUSH B
L0012:  PUSH D
L0013:  PUSH H
L0014:  JMP  Rst2Handler            ;Vblank work
L0017:  .byte $00                   ;unused

;------------------------------------------------------------------------------
; Boot - Choose between the self test and the game.
;------------------------------------------------------------------------------
Boot:
L0018:  IN   INP_DIP                ;DIP b7 = self-test switch
L001A:  ANI  $80
L001C:  JNZ  RamTest                ;On: run the RAM and ROM tests
L001F:  JMP  GameStart              ;Off: start the game

;------------------------------------------------------------------------------
; RamTest - Walking-bit test of all RAM $2000-$3FFF.
;   B = test bit, rotated through all 8 positions. Each pass: write B everywhere;
;   walk back down checking B and replacing it with its complement; walk up
;   again checking the complement and clearing. Wrong bits are OR-ed into D for
;   even addresses and E for odd ones. The stack is not used: RAM is not
;   trusted yet.
;   The coin switch held down at any point leaves for the switch test.
;------------------------------------------------------------------------------
RamTest:
L0022:  MVI  B,$01                  ;First bit to walk
L0024:  LXI  D,$0000                ;DE = bad bits found so far (D even addresses, E odd)
L0027:  LXI  H,WorkRam              ;Start of RAM
;Pass 1, upward: write the pattern and read it straight back
L002A:  OUT  OUT_WATCHDOG           ;Keep the watchdog quiet
L002C:  IN   INP_SWITCH             ;Coin switch down (active low)?
L002E:  ANI  $40
L0030:  JZ   SwitchTest             ;Yes: go to the switch test
L0033:  MOV  M,B                    ;Write the pattern
L0034:  MOV  A,M
L0035:  XRA  B                      ;A = bits that read back wrong
L0036:  JZ   L0048                  ;None
L0039:  MOV  C,A                    ;C = wrong bits
L003A:  MOV  A,L
L003B:  ANI  $01                    ;Even or odd address?
L003D:  MOV  A,C
L003E:  JNZ  L0046                  ;Odd: record in E
L0041:  ORA  D                      ;Even: record in D
L0042:  MOV  D,A
L0043:  JMP  L0048
L0046:  ORA  E                      ;Odd: record in E
L0047:  MOV  E,A
L0048:  INX  H                      ;Next address
L0049:  MOV  A,H
L004A:  CPI  $40                    ;Until $4000
L004C:  JNZ  L002A
;Pass 2, downward: check the pattern, replace it with its complement
L004F:  OUT  OUT_WATCHDOG
L0051:  IN   INP_SWITCH
L0053:  ANI  $40
L0055:  JZ   SwitchTest             ;Coin switch: to the switch test
L0058:  DCX  H                      ;Next address down
L0059:  MOV  A,H
L005A:  CPI  $1F                    ;Below $2000?
L005C:  JZ   L008C                  ;Yes: pass 3
L005F:  MOV  A,M                    ;Pattern still there?
L0060:  XRA  B
L0061:  JZ   L0073
L0064:  MOV  C,A
L0065:  MOV  A,L
L0066:  ANI  $01
L0068:  MOV  A,C
L0069:  JNZ  L0071
L006C:  ORA  D
L006D:  MOV  D,A
L006E:  JMP  L0073
L0071:  ORA  E
L0072:  MOV  E,A
L0073:  MOV  A,B                    ;Write the complement
L0074:  CMA
L0075:  MOV  M,A
L0076:  XRA  M                      ;A = bits that did not take
L0077:  JZ   L004F                  ;None: next address
L007A:  MOV  C,A
L007B:  MOV  A,L
L007C:  ANI  $01
L007E:  MOV  A,C
L007F:  JNZ  L0087
L0082:  ORA  D
L0083:  MOV  D,A
L0084:  JMP  L0089
L0087:  ORA  E
L0088:  MOV  E,A
L0089:  JMP  L004F                  ;Next address
;Pass 3, upward: check the complement, leave RAM cleared
L008C:  OUT  OUT_WATCHDOG
L008E:  IN   INP_SWITCH
L0090:  ANI  $40
L0092:  JZ   SwitchTest             ;Coin switch: to the switch test
L0095:  INX  H
L0096:  MOV  A,H
L0097:  CPI  $40                    ;Until $4000
L0099:  JZ   L00B6                  ;Done: next bit
L009C:  MOV  A,B                    ;Complement still there?
L009D:  CMA
L009E:  XRA  M
L009F:  JZ   L00B1
L00A2:  MOV  C,A
L00A3:  MOV  A,L
L00A4:  ANI  $01
L00A6:  MOV  A,C
L00A7:  JNZ  L00AF
L00AA:  ORA  D
L00AB:  MOV  D,A
L00AC:  JMP  L00B1
L00AF:  ORA  E
L00B0:  MOV  E,A
L00B1:  XRA  A                      ;Leave the byte zero
L00B2:  MOV  M,A
L00B3:  JMP  L008C
L00B6:  MOV  A,B                    ;Next bit position
L00B7:  RLC
L00B8:  MOV  B,A
L00B9:  JNC  L0027                  ;Until the bit falls out of the byte
L00BC:  MOV  A,D                    ;Any bad bit in either half?
L00BD:  ORA  E
L00BE:  JZ   RomTest                ;No: RAM is good, test the ROMs

;------------------------------------------------------------------------------
; RamError - Show the bad RAM bits as 16 columns over the whole screen.
;   DE (the bad-bit word, D15 at the left) is kept in SP. Each bit takes two
;   bytes of every 32-byte line: a solid 8-pixel block if the bit is good, blank
;   if it is bad, then a 2-pixel separator. The pattern is written from $2000 up,
;   so work RAM is overwritten as well. Ends in the self-test wait loop.
;------------------------------------------------------------------------------
RamError:
L00C1:  XCHG                        ;HL = bad-bit word
L00C2:  SPHL                        ;Keep it in SP (no RAM needed)
L00C3:  LXI  D,WorkRam              ;Fill from the start of RAM
L00C6:  MVI  B,$00                  ;256 groups of 32 bytes = all of RAM
L00C8:  LXI  H,$0000                ;HL = the bad-bit word again
L00CB:  DAD  SP
L00CC:  MVI  C,$10                  ;16 bits per line
L00CE:  XRA  A
L00CF:  DAD  H                      ;Next bit into carry
L00D0:  JC   L00D4                  ;Bad bit: leave the block blank
L00D3:  CMA                         ;Good bit: solid block
L00D4:  STAX D
L00D5:  INX  D
L00D6:  MVI  A,$18                  ;Separator column
L00D8:  STAX D
L00D9:  INX  D
L00DA:  DCR  C
L00DB:  JNZ  L00CE                  ;16 bits
L00DE:  DCR  B
L00DF:  JNZ  L00C8                  ;All lines
L00E2:  JMP  SelfTestWait           ;Wait for the self-test switch to go off

;------------------------------------------------------------------------------
; RomTest - Checksum the six ROMs.
;   For each 1K ROM: check byte from RomCheckTable + sum of the 1024 bytes + 1
;   must be 0. For a ROM that fails, its letter (H G F E D C) is printed on line
;   144, starting at column 12. If nothing was printed the whole self test starts
;   over (through Reset), so it repeats for as long as the switch is on.
;------------------------------------------------------------------------------
RomTest:
L00E5:  LXI  SP,$2400               ;RAM is good: the stack can be used
L00E8:  LXI  H,$360C                ;Screen position for the first bad-ROM letter
L00EB:  PUSH H
L00EC:  LXI  H,$0000                ;HL = ROM address
L00EF:  LXI  D,RomCheckTable        ;DE = check byte / letter table
L00F2:  LXI  B,$0400                ;1024 bytes per ROM
L00F5:  LDAX D                      ;Start the sum with the ROM's check byte
L00F6:  INX  D
L00F7:  ADD  M                      ;Add a ROM byte
L00F8:  OUT  OUT_WATCHDOG
L00FA:  INX  H
L00FB:  DCR  C
L00FC:  JNZ  L00F7                  ;256 bytes
L00FF:  DCR  B
L0100:  JNZ  L00F7                  ;4 x 256
L0103:  INR  A                      ;Sum + 1 = 0?
L0104:  JZ   L0111                  ;Yes: ROM good, skip its letter
L0107:  XTHL                        ;HL = screen position, ROM address to the stack
L0108:  XCHG                        ;DE = screen position, HL = the ROM's letter
L0109:  MVI  A,$01                  ;One character
L010B:  CALL DrawString             ;Print the letter; DE moves to the next column
L010E:  XCHG                        ;Back: DE = table, HL = screen position
L010F:  XTHL                        ;Screen position to the stack, HL = ROM address
L0110:  DCX  D                      ;(cancels the INX below: DrawString already stepped past the letter)
L0111:  INX  D                      ;Skip the letter
L0112:  MOV  A,H                    ;End of the last ROM ($1800)?
L0113:  CPI  $18
L0115:  JNZ  L00F2                  ;No: next ROM
L0118:  POP  H                      ;Screen position
L0119:  MOV  A,L
L011A:  CPI  $0C                    ;Still column 12: nothing was printed?
L011C:  JZ   Reset                  ;All ROMs good: run the self test again

;------------------------------------------------------------------------------
; SelfTestWait - Hold the error display until the self-test switch goes off.
;------------------------------------------------------------------------------
SelfTestWait:
L011F:  OUT  OUT_WATCHDOG
L0121:  IN   INP_DIP                ;Self-test switch
L0123:  ANI  $80
L0125:  JZ   Reset                  ;Off: reset (which starts the game)
L0128:  JMP  SelfTestWait           ;Still on: keep waiting

RomCheckTable:
L012B:  .byte $00, $48              ;ROM H $0000-$03FF: check byte, letter shown if the sum is wrong
L012D:  .byte $63, $47              ;ROM G $0400-$07FF: check byte, letter shown if the sum is wrong
L012F:  .byte $B8, $46              ;ROM F $0800-$0BFF: check byte, letter shown if the sum is wrong
L0131:  .byte $7B, $45              ;ROM E $0C00-$0FFF: check byte, letter shown if the sum is wrong
L0133:  .byte $0E, $44              ;ROM D $1000-$13FF: check byte, letter shown if the sum is wrong
L0135:  .byte $17, $43              ;ROM C $1400-$17FF: check byte, letter shown if the sum is wrong
L0137:  .byte $02                   ;not read by the test; presumably the byte adjusted to make ROM H add up

;==============================================================================
; SECTION 2  Interrupt work ($0138-$0475)
;   Everything that touches the screen runs in the two interrupts. Each frame
;   one of them moves and redraws the flying clown and the other does the frame
;   task (seesaw and rider on even frames; balloons, timers and the coin switch
;   on odd frames). Which does which depends on where the flyer is, so that it
;   is never redrawn while the beam is passing over it.
;==============================================================================

;------------------------------------------------------------------------------
; Rst1Handler - Mid-screen interrupt.
;   Flyer above Y $50 (already displayed): update the flyer now and leave the
;   frame task to the vblank interrupt. Otherwise do the frame task now.
;------------------------------------------------------------------------------
Rst1Handler:
L0138:  LHLD FLYER_PTR              ;The clown in the air
L013B:  LXI  B,CL_Y
L013E:  DAD  B
L013F:  MOV  A,M                    ;Its Y
L0140:  SUI  $50                    ;Above line $50?
L0142:  JC   L0146                  ;Yes: A is non-zero
L0145:  XRA  A                      ;No: A = 0
L0146:  STA  FLYER_HIGH
L0149:  JZ   FrameTask              ;Flyer is low: this interrupt does the frame task

;------------------------------------------------------------------------------
; UpdateFlyer - Erase, move and redraw the flying clown, test for contact; then the tune.
;   Skipped while FREEZE is set or while a contact is waiting for HandleContact.
;------------------------------------------------------------------------------
UpdateFlyer:
L014C:  LDA  FREEZE                 ;Frozen for a bonus message?
L014F:  ANA  A
L0150:  JNZ  L016F                  ;Yes: tune only
L0153:  LDA  CONTACT_ROW            ;Contact not handled yet?
L0156:  ANA  A
L0157:  JNZ  L016F                  ;Yes: tune only
L015A:  LHLD FLYER_PTR
L015D:  CALL EraseFlyer             ;Remove the old picture
L0160:  LHLD FLYER_PTR
L0163:  CALL DrawFlyer              ;Move and draw; saves the background it covers
L0166:  LDA  FREEZE_REQ             ;A freeze request takes effect after this last draw
L0169:  STA  FREEZE
L016C:  CALL CheckContact           ;Did the picture land on anything?
L016F:  CALL PlayTune               ;Music, once a frame
L0172:  JMP  IrqExit

;------------------------------------------------------------------------------
; Rst2Handler - Vertical blank interrupt.
;   Reads the paddle, refreshes OUT_MISC (paddle select follows PLAYER), then
;   does whichever half of the frame Rst1Handler left.
;------------------------------------------------------------------------------
Rst2Handler:
L0175:  LDA  PADDLE_ENABLE          ;Paddle wanted (game or switch test)?
L0178:  ANA  A
L0179:  JZ   L0181
L017C:  IN   INP_PADDLE             ;Paddle of the selected player
L017E:  STA  PADDLE_POS
L0181:  LXI  H,OUT3_SHADOW
L0184:  MOV  A,M
L0185:  ANI  $FD                    ;Drop the old paddle select
L0187:  MOV  B,A
L0188:  LDA  PLAYER                 ;PLAYER is $00 or $FF
L018B:  ANI  $02                    ;b1 = paddle select
L018D:  ORA  B
L018E:  MOV  M,A
L018F:  OUT  OUT_MISC               ;Coin counter and paddle select
L0191:  LDA  FLYER_HIGH             ;Did the mid-screen interrupt update the flyer?
L0194:  ANA  A
L0195:  JZ   UpdateFlyer            ;No: update it now

;------------------------------------------------------------------------------
; FrameTask - Once a frame: seesaw and rider (even frames) or balloons and timers (odd frames).
;------------------------------------------------------------------------------
FrameTask:
L0198:  LXI  H,FRAME_CTR
L019B:  INR  M
L019C:  MOV  A,M
L019D:  RAR
L019E:  JC   L01B6                  ;Odd frame
L01A1:  LHLD RIDER_PTR              ;The clown on the seesaw
L01A4:  CALL EraseRider             ;Blank its old picture if asked (it has just landed)
L01A7:  CALL EraseSeesaw            ;Erase the seesaw, take the new X
L01AA:  CALL DrawSeesaw             ;Draw the seesaw
L01AD:  LHLD RIDER_PTR
L01B0:  CALL DrawRider              ;Draw the rider on its low end
L01B3:  JMP  IrqExit
;Odd frame: one of the six balloon passes, then the timers
L01B6:  LXI  H,FrameTimers          ;Everything below returns to FrameTimers
L01B9:  PUSH H
L01BA:  LDA  FREEZE                 ;Frozen: balloons stand still
L01BD:  ANA  A
L01BE:  RNZ
L01BF:  LXI  H,BALLOON_PHASE        ;Next of the six passes
L01C2:  MOV  A,M
L01C3:  INR  A
L01C4:  CPI  $06
L01C6:  JC   L01CA
L01C9:  XRA  A
L01CA:  MOV  M,A
L01CB:  MOV  C,A
L01CC:  MVI  B,$00
L01CE:  LXI  H,BalloonTasks         ;4 bytes per entry
L01D1:  DAD  B
L01D2:  DAD  B
L01D3:  DAD  B
L01D4:  DAD  B
L01D5:  MOV  E,M                    ;DE = first balloon of the pass
L01D6:  INX  H
L01D7:  MOV  D,M
L01D8:  INX  H
L01D9:  MOV  A,M                    ;HL = routine
L01DA:  INX  H
L01DB:  MOV  H,M
L01DC:  MOV  L,A
L01DD:  PCHL                        ;MoveBalloonsRight / MoveBalloonsLeft with DE

;------------------------------------------------------------------------------
; FrameTimers - Odd-frame tail: timers and coin switch.
;------------------------------------------------------------------------------
FrameTimers:
L01DE:  CALL TickSecondTimer
L01E1:  CALL TickTimers
L01E4:  CALL CoinSwitch

;------------------------------------------------------------------------------
; IrqExit - Restore the registers and return from the interrupt.
;------------------------------------------------------------------------------
IrqExit:
L01E7:  POP  H
L01E8:  POP  D
L01E9:  POP  B
L01EA:  POP  PSW
L01EB:  EI
L01EC:  RET

;------------------------------------------------------------------------------
; TickSecondTimer - Count TMR_TIMEOUT down once every 30 odd frames (about a second).
;   Nothing happens while the previous expiry is still waiting in EVT_TIMEOUT.
;------------------------------------------------------------------------------
TickSecondTimer:
L01ED:  LXI  D,EVT_TIMEOUT
L01F0:  LDAX D                      ;Last event not taken yet?
L01F1:  ANA  A
L01F2:  RNZ
L01F3:  MOV  B,A                    ;B = 0: expiry bits
L01F4:  LXI  H,SECOND_PRESCALE
L01F7:  DCR  M                      ;One second gone?
L01F8:  RNZ
L01F9:  MVI  M,$1E                  ;Reload: 30 odd frames
L01FB:  MVI  C,$01                  ;One timer
L01FD:  LXI  H,TMR_TIMEOUT
L0200:  CALL TickTimerList
L0203:  STAX D                      ;EVT_TIMEOUT b0 = expired
L0204:  RET

;------------------------------------------------------------------------------
; TickTimers - Count the 30 Hz timers down and post the ones that reach zero.
;   Eight timers at TMR_SCRIPT -> EVT_TIMERS, three at TMR_COIN_CTR ->
;   EVT_TIMERS2. Each group is skipped while its event byte is still non-zero.
;------------------------------------------------------------------------------
TickTimers:
L0205:  LXI  H,TMR_SCRIPT
L0208:  LXI  D,EVT_TIMERS
L020B:  LDAX D                      ;Events not taken yet?
L020C:  ANA  A
L020D:  RNZ
L020E:  MOV  B,A
L020F:  MVI  C,$08                  ;Eight timers
L0211:  CALL TickTimerList
L0214:  STAX D                      ;b7 = TMR_SCRIPT ... b0 = TMR_REFILL
L0215:  LXI  D,EVT_TIMERS2
L0218:  LDAX D                      ;Events not taken yet?
L0219:  ANA  A
L021A:  RNZ
L021B:  MOV  B,A
L021C:  MVI  C,$03                  ;Three timers follow the eight
L021E:  CALL TickTimerList
L0221:  STAX D                      ;b2 = TMR_COIN_CTR, b1 = TMR_TUMBLE, b0 = TMR_FREEZE
L0222:  RET

;------------------------------------------------------------------------------
; TickTimerList - Decrement C timers at HL; shift a 1 into B for each that reaches zero.
;   A timer that is already 0 stays 0 and posts nothing. Returns A = B.
;------------------------------------------------------------------------------
TickTimerList:
L0223:  MOV  A,M
L0224:  ANA  A
L0225:  JZ   L022D                  ;Stopped
L0228:  DCR  M                      ;Count down
L0229:  JNZ  L022D                  ;Still running
L022C:  STC                         ;Just expired
L022D:  MOV  A,B                    ;Shift the result bit into B
L022E:  RAL
L022F:  MOV  B,A
L0230:  INX  H
L0231:  DCR  C
L0232:  JNZ  TickTimerList          ;Next timer
L0235:  RET
L0236:  .byte $00                   ;unused

;------------------------------------------------------------------------------
; PlayTune - Step the tune player, once a frame.
;   A tune is: tempo byte ($80 + frames per beat), then (beats, note) pairs,
;   then 0. The note is an index into NoteTable; with b7 set it runs straight
;   into the next note, otherwise one frame of silence follows it. A tempo byte
;   also turns the sound board on.
;------------------------------------------------------------------------------
PlayTune:
L0237:  LDA  TUNE_ON                ;Tune playing?
L023A:  ANA  A
L023B:  RZ
L023C:  LXI  H,TUNE_TICKS           ;Frames left in this beat
L023F:  MOV  A,M
L0240:  ANA  A
L0241:  JZ   L0246                  ;Beat over
L0244:  DCR  M
L0245:  RET
L0246:  INX  H                      ;Beats left in this note
L0247:  MOV  A,M
L0248:  ANA  A
L0249:  JZ   L0253                  ;Note over
L024C:  DCR  M
L024D:  DCX  H                      ;Start the next beat
L024E:  LDA  TUNE_TEMPO
L0251:  MOV  M,A
L0252:  RET
L0253:  INX  H                      ;A gap owed after the note?
L0254:  MOV  A,M
L0255:  ANA  A
L0256:  JZ   L025E                  ;No: next note
L0259:  DCR  M
L025A:  XRA  A                      ;Yes: one frame of silence
L025B:  OUT  OUT_TONE_LO
L025D:  RET
L025E:  LHLD TUNE_PTR               ;Next tune byte
L0261:  MOV  A,M
L0262:  ANA  A
L0263:  JNZ  L0271                  ;Not the end
L0266:  XRA  A                      ;End of tune: tone off
L0267:  OUT  OUT_TONE_LO
L0269:  LDA  GAME_ACTIVE            ;In a game the other sounds stay enabled
L026C:  ANA  A
L026D:  RNZ
L026E:  OUT  OUT_SOUND              ;Attract mode: sound board off
L0270:  RET
L0271:  JP   L027F                  ;Plain beat count
L0274:  ANI  $7F                    ;Tempo byte: frames per beat
L0276:  STA  TUNE_TEMPO
L0279:  MVI  A,$08                  ;Sound enable
L027B:  OUT  OUT_SOUND
L027D:  INX  H                      ;The beat count follows
L027E:  MOV  A,M
L027F:  STA  TUNE_BEATS             ;Beats for this note
L0282:  INX  H
L0283:  LDA  TUNE_TEMPO             ;B = frames for the first beat
L0286:  MOV  B,A
L0287:  MOV  A,M                    ;The note
L0288:  ANA  A
L0289:  JM   L0292                  ;b7: no gap
L028C:  MVI  A,$01                  ;One frame of silence after the note,
L028E:  STA  TUNE_GAP
L0291:  DCR  B                      ;taken out of its first beat
L0292:  MOV  A,B
L0293:  STA  TUNE_TICKS
L0296:  MOV  A,M
L0297:  INX  H
L0298:  SHLD TUNE_PTR               ;Tune pointer past the note
L029B:  ANI  $7F                    ;Note number
L029D:  MOV  C,A
;Program the tone generator with note C
L029E:  MVI  B,$00
L02A0:  LXI  H,NoteTable
L02A3:  DAD  B
L02A4:  DAD  B                      ;Two bytes per note
L02A5:  MOV  A,M
L02A6:  OUT  OUT_TONE_LO            ;Enable bit and low period bits
L02A8:  INX  H
L02A9:  MOV  A,M
L02AA:  OUT  OUT_TONE_HI            ;High period bits
L02AC:  RET
L02AD:  .byte $00                   ;unused

;------------------------------------------------------------------------------
; NoteTable - Tone generator settings for notes $00-$25.
;   Byte 0 goes to OUT_TONE_LO (b0 enable, b1-b5 low bits), byte 1 to
;   OUT_TONE_HI (high 6 bits). The 12-bit counter preset is 64 x high + 2 x low;
;   the counter runs from it up to 4096 at 998.4 kHz and toggles the output, so
;   the tone is 998400 / (4096 - preset) / 2 Hz (per MAME's model of the board):
;   three octaves of semitones.
;------------------------------------------------------------------------------
NoteTable:
L02AE:  .byte $00, $00              ;note $00: rest (tone off)
L02B0:  .byte $3F, $13              ;note $01: preset 1278, 177 Hz
L02B2:  .byte $1D, $16              ;note $02: preset 1436, 188 Hz
L02B4:  .byte $33, $18              ;note $03: preset 1586, 199 Hz
L02B6:  .byte $3F, $1A              ;note $04: preset 1726, 211 Hz
L02B8:  .byte $05, $1D              ;note $05: preset 1860, 223 Hz
L02BA:  .byte $01, $1F              ;note $06: preset 1984, 236 Hz
L02BC:  .byte $39, $20              ;note $07: preset 2104, 251 Hz
L02BE:  .byte $27, $22              ;note $08: preset 2214, 265 Hz
L02C0:  .byte $11, $24              ;note $09: preset 2320, 281 Hz
L02C2:  .byte $35, $25              ;note $0A: preset 2420, 298 Hz
L02C4:  .byte $13, $27              ;note $0B: preset 2514, 316 Hz
L02C6:  .byte $2B, $28              ;note $0C: preset 2602, 334 Hz
L02C8:  .byte $3F, $29              ;note $0D: preset 2686, 354 Hz
L02CA:  .byte $0F, $2B              ;note $0E: preset 2766, 375 Hz
L02CC:  .byte $19, $2C              ;note $0F: preset 2840, 397 Hz
L02CE:  .byte $1F, $2D              ;note $10: preset 2910, 421 Hz
L02D0:  .byte $21, $2E              ;note $11: preset 2976, 446 Hz
L02D2:  .byte $21, $2F              ;note $12: preset 3040, 473 Hz
L02D4:  .byte $1D, $30              ;note $13: preset 3100, 501 Hz
L02D6:  .byte $15, $31              ;note $14: preset 3156, 531 Hz
L02D8:  .byte $09, $32              ;note $15: preset 3208, 562 Hz
L02DA:  .byte $3B, $32              ;note $16: preset 3258, 596 Hz
L02DC:  .byte $29, $33              ;note $17: preset 3304, 630 Hz
L02DE:  .byte $17, $34              ;note $18: preset 3350, 669 Hz
L02E0:  .byte $3F, $34              ;note $19: preset 3390, 707 Hz
L02E2:  .byte $27, $35              ;note $1A: preset 3430, 750 Hz
L02E4:  .byte $0D, $36              ;note $1B: preset 3468, 795 Hz
L02E6:  .byte $31, $36              ;note $1C: preset 3504, 843 Hz
L02E8:  .byte $11, $37              ;note $1D: preset 3536, 891 Hz
L02EA:  .byte $31, $37              ;note $1E: preset 3568, 945 Hz
L02EC:  .byte $0F, $38              ;note $1F: preset 3598, 1002 Hz
L02EE:  .byte $2B, $38              ;note $20: preset 3626, 1062 Hz
L02F0:  .byte $05, $39              ;note $21: preset 3652, 1124 Hz
L02F2:  .byte $1D, $39              ;note $22: preset 3676, 1189 Hz
L02F4:  .byte $35, $39              ;note $23: preset 3700, 1261 Hz
L02F6:  .byte $0B, $3A              ;note $24: preset 3722, 1335 Hz
L02F8:  .byte $21, $3A              ;note $25: preset 3744, 1418 Hz
L02FA:  .byte $00                   ;unused

;------------------------------------------------------------------------------
; DrawSeesaw - Animate and draw the seesaw.
;   While it is tipping (b6) the picture number steps 0..4 or 4..0; at the end
;   b6 is cleared and b5 (which end is down) flips. The picture is 40 pixels
;   wide, drawn bottom row first from line 211 upward through the shifter.
;------------------------------------------------------------------------------
DrawSeesaw:
L02FB:  LXI  H,SEESAW_STATE
L02FE:  MOV  A,M                    ;On screen?
L02FF:  ANA  A
L0300:  RP
L0301:  MOV  A,M
L0302:  ANI  $40                    ;Tipping?
L0304:  JZ   L0326                  ;No: just draw
L0307:  MOV  A,M
L0308:  ANI  $20                    ;Which way?
L030A:  JZ   L031F                  ;Left end is down: run 4 to 0
L030D:  INR  M                      ;Right end is down: run 0 to 4
L030E:  MOV  A,M
L030F:  ANI  $0F
L0311:  CPI  $04
L0313:  JC   L0326                  ;Not there yet
L0316:  MOV  A,M
L0317:  ANI  $BF                    ;Tipped: stop,
L0319:  XRI  $20                    ;and the other end is down now
L031B:  MOV  M,A
L031C:  JMP  L0326
L031F:  DCR  M
L0320:  MOV  A,M
L0321:  ANI  $0F
L0323:  JZ   L0316                  ;Reached 0: stop
L0326:  MOV  A,M
L0327:  ANI  $0F                    ;Picture number
L0329:  MOV  C,A
L032A:  MVI  B,$00
L032C:  INX  H
L032D:  MOV  A,M                    ;X
L032E:  MOV  E,A
L032F:  ANI  $07                    ;X within the byte
L0331:  OUT  OUT_SHIFT_AMT          ;to the shifter
L0333:  MOV  A,E
L0334:  RAR                         ;X / 8
L0335:  RAR
L0336:  RAR
L0337:  ANI  $1F
L0339:  ORI  $60                    ;+ $60:
L033B:  MOV  E,A
L033C:  MVI  D,$3E                  ;DE = $3E60 + X/8: line 211
L033E:  LXI  H,SeesawPictures       ;Picture pointers
L0341:  DAD  B
L0342:  DAD  B
L0343:  MOV  A,M
L0344:  INX  H
L0345:  MOV  H,M
L0346:  MOV  L,A
L0347:  XCHG                        ;DE = picture, HL = screen
L0348:  LDAX D                      ;B = rows
L0349:  INX  D
L034A:  MOV  B,A
L034B:  CALL ShiftedByte            ;Five bytes of the row
L034E:  CALL ShiftedByte
L0351:  CALL ShiftedByte
L0354:  CALL ShiftedByte
L0357:  CALL ShiftedByte
L035A:  XRA  A
L035B:  OUT  OUT_SHIFT_DATA         ;Flush the shifter into a sixth byte
L035D:  IN   INP_SHIFT
L035F:  MOV  M,A
L0360:  MOV  A,B
L0361:  LXI  B,$FFDB                ;One line up (6 bytes written, 5 pointer steps: -37)
L0364:  DAD  B
L0365:  MOV  B,A
L0366:  DCR  B
L0367:  JNZ  L034B                  ;Next row
L036A:  RET

;------------------------------------------------------------------------------
; ShiftedByte - Next picture byte through the shifter to the screen (overwrites).
;------------------------------------------------------------------------------
ShiftedByte:
L036B:  LDAX D
L036C:  INX  D
L036D:  OUT  OUT_SHIFT_DATA
L036F:  IN   INP_SHIFT
L0371:  MOV  M,A
L0372:  INX  H
L0373:  RET

SeesawPictures:
L0374:  .word SeesawPic0            ;picture 0
L0376:  .word SeesawPic1            ;picture 1
L0378:  .word SeesawPic2            ;picture 2
L037A:  .word SeesawPic3            ;picture 3
L037C:  .word SeesawPic4            ;picture 4

SeesawPic0:
L037E:  .byte $08                   ;8 rows of 5 bytes, bottom row first
L037F:  .byte $00, $00, $7E, $00, $F8 ;.................######............#####
L0384:  .byte $00, $00, $3C, $C0, $07 ;..................####........#####.....
L0389:  .byte $00, $00, $18, $3E, $00 ;...................##....#####..........
L038E:  .byte $00, $00, $F0, $01, $00 ;....................#####...............
L0393:  .byte $00, $80, $0F, $00, $00 ;...............#####....................
L0398:  .byte $00, $7C, $00, $00, $00 ;..........#####.........................
L039D:  .byte $E0, $03, $00, $00, $00 ;.....#####..............................
L03A2:  .byte $1F, $00, $00, $00, $00 ;#####...................................

SeesawPic1:
L03A7:  .byte $05                   ;5 rows of 5 bytes, bottom row first
L03A8:  .byte $00, $00, $7E, $00, $F8 ;.................######............#####
L03AD:  .byte $00, $00, $3C, $C0, $07 ;..................####........#####.....
L03B2:  .byte $00, $00, $18, $3E, $00 ;...................##....#####..........
L03B7:  .byte $00, $00, $F0, $01, $00 ;....................#####...............
L03BC:  .byte $FF, $FF, $0F, $00, $00 ;####################....................

SeesawPic2:
L03C1:  .byte $05                   ;5 rows of 5 bytes, bottom row first
L03C2:  .byte $00, $00, $7E, $00, $F8 ;.................######............#####
L03C7:  .byte $1F, $00, $3C, $C0, $07 ;#####.............####........#####.....
L03CC:  .byte $E0, $03, $18, $3E, $00 ;.....#####.........##....#####..........
L03D1:  .byte $00, $7C, $F0, $01, $00 ;..........#####.....#####...............
L03D6:  .byte $00, $80, $0F, $00, $00 ;...............#####....................

SeesawPic3:
L03DB:  .byte $05                   ;5 rows of 5 bytes, bottom row first
L03DC:  .byte $1F, $00, $7E, $00, $00 ;#####............######.................
L03E1:  .byte $E0, $03, $3C, $00, $00 ;.....#####........####..................
L03E6:  .byte $00, $7C, $18, $00, $00 ;..........#####....##...................
L03EB:  .byte $00, $80, $0F, $FE, $FF ;...............#####.....###############
L03F0:  .byte $00, $00, $F0, $01, $00 ;....................#####...............

SeesawPic4:
L03F5:  .byte $08                   ;8 rows of 5 bytes, bottom row first
L03F6:  .byte $1F, $00, $7E, $00, $00 ;#####............######.................
L03FB:  .byte $E0, $03, $3C, $00, $00 ;.....#####........####..................
L0400:  .byte $00, $7C, $18, $00, $00 ;..........#####....##...................
L0405:  .byte $00, $80, $0F, $00, $00 ;...............#####....................
L040A:  .byte $00, $00, $F0, $01, $00 ;....................#####...............
L040F:  .byte $00, $00, $00, $3E, $00 ;.........................#####..........
L0414:  .byte $00, $00, $00, $C0, $07 ;..............................#####.....
L0419:  .byte $00, $00, $00, $00, $F8 ;...................................#####
L041E:  .byte $00                   ;unused

;------------------------------------------------------------------------------
; CoinSwitch - Watch the coin switch; count a coin on the press edge.
;------------------------------------------------------------------------------
CoinSwitch:
L041F:  LXI  H,COIN_SW_PREV
L0422:  IN   INP_SWITCH             ;Coin switch is active low
L0424:  CMA
L0425:  ANI  $40
L0427:  MOV  B,A
L0428:  XRA  M                      ;Changed?
L0429:  RZ                          ;No
L042A:  MOV  M,B                    ;Remember the new state
L042B:  MOV  A,B
L042C:  ANA  A
L042D:  RZ                          ;Released
L042E:  LXI  H,OUT3_SHADOW
L0431:  MOV  A,M
L0432:  ORI  $01                    ;Coin counter on
L0434:  MOV  M,A
L0435:  MVI  A,$0A                  ;for 10 odd frames (TMR_COIN_CTR turns it off)
L0437:  STA  TMR_COIN_CTR
L043A:  LXI  H,COINS
L043D:  INR  M                      ;One more coin
L043E:  RET

;------------------------------------------------------------------------------
; CheckContact - Did the flyer's last picture touch anything?
;   Looks at the background bytes DrawFlyer saved (3 per row). Only the 16
;   pixels in the middle of the 24 count: the high nibble of byte 0, all of byte
;   1, the low nibble of byte 2. The first row with a set pixel gives
;   CONTACT_ROW = row + 1, which HandleContact (main loop) acts on.
;------------------------------------------------------------------------------
CheckContact:
L043F:  LDA  TMR_HIT_LOCKOUT        ;Just launched or just popped a balloon: ignore
L0442:  ANA  A
L0443:  RNZ
L0444:  LHLD FLYER_PTR              ;The flyer
L0447:  MOV  A,M
L0448:  ANA  A
L0449:  RP                          ;Not in use
L044A:  ANI  $60                    ;Drawn since it was last erased?
L044C:  RZ
L044D:  MOV  A,M
L044E:  ANI  $08                    ;Splatted
L0450:  RNZ
L0451:  LXI  B,CL_ROWS
L0454:  DAD  B
L0455:  MOV  C,M                    ;C = rows drawn
L0456:  MOV  B,C
L0457:  INX  H                      ;Skip the width
L0458:  INX  H
L0459:  MOV  A,M                    ;Row: high nibble of the first byte
L045A:  ANI  $F0
L045C:  INX  H
L045D:  ORA  M                      ;and the whole second byte
L045E:  JNZ  L046E                  ;Something was there
L0461:  INX  H
L0462:  MOV  A,M
L0463:  ANI  $0F                    ;Low nibble of the third byte
L0465:  JNZ  L046E
L0468:  INX  H
L0469:  DCR  B
L046A:  JNZ  L0459                  ;Next row
L046D:  RET
L046E:  MOV  A,C                    ;Rows done before this one,
L046F:  SUB  B
L0470:  INR  A                      ;+ 1
L0471:  STA  CONTACT_ROW
L0474:  RET
L0475:  .byte $00                   ;unused

;==============================================================================
; SECTION 3  Drawing ($0476-$0A40)
;   Text, the screen address calculation, and the erase / draw routines for the
;   two clowns with their pictures. Sprites are positioned to the pixel with the
;   MB14241 shifter: OUT_SHIFT_AMT gets X AND 7, each picture byte goes to
;   OUT_SHIFT_DATA and the shifted byte is read from INP_SHIFT; a final 0 pushes
;   out the bits that spill into the next screen byte.
;==============================================================================

;------------------------------------------------------------------------------
; EraseSeesaw - Blank the seesaw where it was last drawn and take its new X.
;   SEESAW_X = PADDLE_POS limited to $D7. The area blanked is 48 pixels wide and
;   16 lines up from line 211, which also removes the rider. The code blanks
;   only the 8 seesaw lines when the rider's state asks for its own box to be
;   blanked (b5), but FrameTask calls EraseRider first, which clears that bit,
;   so the 8-line case never runs.
;------------------------------------------------------------------------------
EraseSeesaw:
L0476:  LXI  H,SEESAW_STATE
L0479:  MOV  A,M                    ;On screen?
L047A:  ANA  A
L047B:  RP
L047C:  INX  H
L047D:  MOV  B,M                    ;B = X it was drawn at
L047E:  LDA  PADDLE_POS             ;Wanted X
L0481:  CPI  $D8                    ;Limit to $D7 (40-pixel seesaw, 256-pixel screen)
L0483:  JC   L0488
L0486:  MVI  A,$D7
L0488:  STA  SEESAW_X               ;New X
L048B:  MOV  M,A                    ;for the next draw
L048C:  MOV  A,B                    ;Old X / 8
L048D:  RAR
L048E:  RAR
L048F:  RAR
L0490:  ANI  $1F
L0492:  ORI  $60                    ;+ $60:
L0494:  MOV  E,A
L0495:  MVI  D,$3E                  ;DE = $3E60 + X/8: line 211
L0497:  LHLD RIDER_PTR              ;The rider
L049A:  MOV  A,M
L049B:  ANI  $20                    ;still to blank its own box?
L049D:  LXI  B,$0010                ;B = 0, 16 lines
L04A0:  JZ   L04A5                  ;No (always): seesaw and rider
L04A3:  MVI  C,$08                  ;Yes: the 8 seesaw lines only (never reached)
L04A5:  XCHG
L04A6:  LXI  D,$FFDB                ;One line up (-37 after 5 steps)
L04A9:  MOV  M,B                    ;Six bytes of zeros
L04AA:  INX  H
L04AB:  MOV  M,B
L04AC:  INX  H
L04AD:  MOV  M,B
L04AE:  INX  H
L04AF:  MOV  M,B
L04B0:  INX  H
L04B1:  MOV  M,B
L04B2:  INX  H
L04B3:  MOV  M,B
L04B4:  DAD  D
L04B5:  DCR  C
L04B6:  JNZ  L04A9                  ;Next line up
L04B9:  RET
L04BA:  .byte $00                   ;unused

;------------------------------------------------------------------------------
; DrawString - Draw A characters from HL at screen address DE.
;   Characters are 8 x 10 pixels at byte columns (no shifter), 1 byte per
;   character: '0'-'9', '@' (blank), 'A'-'W'. The font has no X Y Z: the Q
;   glyph is drawn as Y and the K glyph is a down arrow. A code below '0' skips
;   ('0' - code) columns instead, moving 16 lines down when it runs into the
;   next screen line. The ten glyph rows go to the ten lines below DE's own line
;   (the first row is written at DE + 32). Returns DE after the last character,
;   HL after the last byte read and A = 0.
;------------------------------------------------------------------------------
DrawString:
L04BB:  PUSH PSW                    ;Characters left
L04BC:  MOV  A,M                    ;Next character
L04BD:  INX  H
L04BE:  SUI  $30                    ;'0' and up?
L04C0:  JP   L04D4                  ;Yes: draw it
L04C3:  MOV  B,A                    ;B = minus the columns to skip
L04C4:  INX  D                      ;One column right
L04C5:  MOV  A,E                    ;Wrapped onto the next screen line?
L04C6:  ANI  $1F
L04C8:  JNZ  L04CD                  ;No
L04CB:  INR  D                      ;Yes: 512 bytes = 16 lines further down
L04CC:  INR  D
L04CD:  INR  B
L04CE:  JNZ  L04C4                  ;More columns
L04D1:  JMP  L04BC                  ;The skip does not count as a character
L04D4:  PUSH H
L04D5:  PUSH D
L04D6:  CALL GlyphAddr              ;DE = glyph, HL = screen address, B = 0
L04D9:  MVI  C,$20                  ;32 bytes per screen line
L04DB:  DAD  B                      ;The first row goes one line below DE
L04DC:  MVI  A,$0A                  ;10 rows
L04DE:  PUSH PSW
L04DF:  LDAX D                      ;Glyph row
L04E0:  INX  D
L04E1:  MOV  M,A                    ;straight to the screen
L04E2:  DAD  B                      ;Next line
L04E3:  POP  PSW
L04E4:  DCR  A
L04E5:  JNZ  L04DE
L04E8:  POP  D
L04E9:  POP  H
L04EA:  INX  D                      ;Next column
L04EB:  POP  PSW
L04EC:  DCR  A
L04ED:  JNZ  DrawString             ;More characters
L04F0:  RET

;------------------------------------------------------------------------------
; DrawBigString - Draw A characters from HL at DE, four times as wide and on every other line.
;   Each glyph bit becomes 4 pixels and each glyph row is written to one line of
;   a pair, so a character is 32 pixels wide and 20 lines tall with the lines
;   between left as they are. The next character starts 4 bytes to the right.
;------------------------------------------------------------------------------
DrawBigString:
L04F1:  PUSH PSW
L04F2:  MOV  A,M                    ;Character
L04F3:  SUI  $30                    ;(no skip codes here)
L04F5:  INX  H
L04F6:  PUSH H
L04F7:  CALL GlyphAddr              ;DE = glyph, HL = screen address, B = 0
L04FA:  MVI  A,$0A                  ;10 rows
L04FC:  PUSH H
L04FD:  PUSH PSW
L04FE:  LDAX D                      ;Glyph row
L04FF:  INX  D
L0500:  CALL TwoBitsWide            ;Two bits -> one screen byte, four times
L0503:  CALL TwoBitsWide
L0506:  CALL TwoBitsWide
L0509:  CALL TwoBitsWide
L050C:  POP  PSW
L050D:  POP  H
L050E:  MVI  C,$40                  ;Two lines down from the start of this row
L0510:  DAD  B
L0511:  DCR  A
L0512:  JNZ  L04FC
L0515:  LXI  B,$FD84                ;Back up the 20 lines and right 4 bytes
L0518:  DAD  B
L0519:  XCHG                        ;DE = next screen position
L051A:  POP  H
L051B:  POP  PSW
L051C:  DCR  A
L051D:  JNZ  DrawBigString          ;More characters
L0520:  RET

;------------------------------------------------------------------------------
; TwoBitsWide - Low two bits of A, each widened to 4 pixels, as one screen byte at HL.
;------------------------------------------------------------------------------
TwoBitsWide:
L0521:  RAR                         ;Bit 0 ->
L0522:  MVI  C,$00
L0524:  JNC  L0529
L0527:  MVI  C,$0F                  ;pixels 0-3
L0529:  RAR                         ;Bit 1 ->
L052A:  PUSH PSW
L052B:  MVI  A,$00
L052D:  JNC  L0532
L0530:  MVI  A,$F0                  ;pixels 4-7
L0532:  ORA  C
L0533:  MOV  M,A
L0534:  INX  H
L0535:  POP  PSW
L0536:  RET

;------------------------------------------------------------------------------
; ScreenAddr - DE = video RAM address of pixel X = E, Y = D.
;   (Y * 256 + X) / 8 + $2400. Leaves B = 0.
;------------------------------------------------------------------------------
ScreenAddr:
L0537:  MVI  B,$03                  ;Three shifts
L0539:  XRA  A
L053A:  MOV  A,D                    ;DE >> 1
L053B:  RAR
L053C:  MOV  D,A
L053D:  MOV  A,E
L053E:  RAR
L053F:  MOV  E,A
L0540:  DCR  B
L0541:  JNZ  L0539
L0544:  MOV  A,D
L0545:  ADI  $24                    ;+ $2400
L0547:  MOV  D,A
L0548:  RET

;------------------------------------------------------------------------------
; GlyphAddr - DE = font glyph for character code A - '0'; HL = the old DE; B = 0.
;   Digits are glyphs 1-10, '@' 11, 'A'-'W' 12-34: the six codes between '9'
;   and '@' are skipped. DrawString relies on the XCHG to get its screen address
;   into HL.
;------------------------------------------------------------------------------
GlyphAddr:
L0549:  INR  A                      ;Glyph numbers start at 1
L054A:  CPI  $0B                    ;A digit?
L054C:  JM   L0551
L054F:  SUI  $06                    ;No: skip the six codes ':' to '?'
L0551:  LXI  H,Font-10              ;Glyph 1 is at Font
L0554:  LXI  B,$000A                ;Ten bytes per glyph
L0557:  DAD  B
L0558:  DCR  A
L0559:  JNZ  L0557
L055C:  XCHG                        ;DE = glyph, HL = caller's DE
L055D:  RET

;------------------------------------------------------------------------------
; Font - 34 glyphs of 10 rows, one byte per row, bit 0 at the left.
;   '0'-'9', '@' (blank), 'A'-'W'. The Q position holds a Y and the K position a
;   down arrow.
;------------------------------------------------------------------------------
Font:
L055E:  .byte $3C                   ;..####..  '0' (0)
L055F:  .byte $7E                   ;.######.
L0560:  .byte $66                   ;.##..##.
L0561:  .byte $66                   ;.##..##.
L0562:  .byte $66                   ;.##..##.
L0563:  .byte $66                   ;.##..##.
L0564:  .byte $66                   ;.##..##.
L0565:  .byte $66                   ;.##..##.
L0566:  .byte $7E                   ;.######.
L0567:  .byte $3C                   ;..####..
L0568:  .byte $18                   ;...##...  '1' (1)
L0569:  .byte $1C                   ;..###...
L056A:  .byte $18                   ;...##...
L056B:  .byte $18                   ;...##...
L056C:  .byte $18                   ;...##...
L056D:  .byte $18                   ;...##...
L056E:  .byte $18                   ;...##...
L056F:  .byte $18                   ;...##...
L0570:  .byte $3C                   ;..####..
L0571:  .byte $3C                   ;..####..
L0572:  .byte $3C                   ;..####..  '2' (2)
L0573:  .byte $7E                   ;.######.
L0574:  .byte $66                   ;.##..##.
L0575:  .byte $60                   ;.....##.
L0576:  .byte $7C                   ;..#####.
L0577:  .byte $3E                   ;.#####..
L0578:  .byte $06                   ;.##.....
L0579:  .byte $06                   ;.##.....
L057A:  .byte $7E                   ;.######.
L057B:  .byte $7E                   ;.######.
L057C:  .byte $3C                   ;..####..  '3' (3)
L057D:  .byte $7E                   ;.######.
L057E:  .byte $66                   ;.##..##.
L057F:  .byte $60                   ;.....##.
L0580:  .byte $38                   ;...###..
L0581:  .byte $78                   ;...####.
L0582:  .byte $60                   ;.....##.
L0583:  .byte $66                   ;.##..##.
L0584:  .byte $7E                   ;.######.
L0585:  .byte $3C                   ;..####..
L0586:  .byte $66                   ;.##..##.  '4' (4)
L0587:  .byte $66                   ;.##..##.
L0588:  .byte $66                   ;.##..##.
L0589:  .byte $66                   ;.##..##.
L058A:  .byte $7E                   ;.######.
L058B:  .byte $7E                   ;.######.
L058C:  .byte $60                   ;.....##.
L058D:  .byte $60                   ;.....##.
L058E:  .byte $60                   ;.....##.
L058F:  .byte $60                   ;.....##.
L0590:  .byte $3E                   ;.#####..  '5' (5)
L0591:  .byte $3E                   ;.#####..
L0592:  .byte $06                   ;.##.....
L0593:  .byte $06                   ;.##.....
L0594:  .byte $3E                   ;.#####..
L0595:  .byte $7E                   ;.######.
L0596:  .byte $60                   ;.....##.
L0597:  .byte $66                   ;.##..##.
L0598:  .byte $7E                   ;.######.
L0599:  .byte $3C                   ;..####..
L059A:  .byte $3C                   ;..####..  '6' (6)
L059B:  .byte $3E                   ;.#####..
L059C:  .byte $06                   ;.##.....
L059D:  .byte $06                   ;.##.....
L059E:  .byte $3E                   ;.#####..
L059F:  .byte $7E                   ;.######.
L05A0:  .byte $66                   ;.##..##.
L05A1:  .byte $66                   ;.##..##.
L05A2:  .byte $7E                   ;.######.
L05A3:  .byte $3C                   ;..####..
L05A4:  .byte $7E                   ;.######.  '7' (7)
L05A5:  .byte $7E                   ;.######.
L05A6:  .byte $60                   ;.....##.
L05A7:  .byte $70                   ;....###.
L05A8:  .byte $30                   ;....##..
L05A9:  .byte $38                   ;...###..
L05AA:  .byte $18                   ;...##...
L05AB:  .byte $1C                   ;..###...
L05AC:  .byte $0C                   ;..##....
L05AD:  .byte $0C                   ;..##....
L05AE:  .byte $3C                   ;..####..  '8' (8)
L05AF:  .byte $7E                   ;.######.
L05B0:  .byte $66                   ;.##..##.
L05B1:  .byte $66                   ;.##..##.
L05B2:  .byte $3C                   ;..####..
L05B3:  .byte $7E                   ;.######.
L05B4:  .byte $66                   ;.##..##.
L05B5:  .byte $66                   ;.##..##.
L05B6:  .byte $7E                   ;.######.
L05B7:  .byte $3C                   ;..####..
L05B8:  .byte $3C                   ;..####..  '9' (9)
L05B9:  .byte $7E                   ;.######.
L05BA:  .byte $66                   ;.##..##.
L05BB:  .byte $66                   ;.##..##.
L05BC:  .byte $7E                   ;.######.
L05BD:  .byte $7C                   ;..#####.
L05BE:  .byte $60                   ;.....##.
L05BF:  .byte $60                   ;.....##.
L05C0:  .byte $7C                   ;..#####.
L05C1:  .byte $3C                   ;..####..
L05C2:  .byte $00                   ;........  '@' (blank)
L05C3:  .byte $00                   ;........
L05C4:  .byte $00                   ;........
L05C5:  .byte $00                   ;........
L05C6:  .byte $00                   ;........
L05C7:  .byte $00                   ;........
L05C8:  .byte $00                   ;........
L05C9:  .byte $00                   ;........
L05CA:  .byte $00                   ;........
L05CB:  .byte $00                   ;........
L05CC:  .byte $18                   ;...##...  'A' (A)
L05CD:  .byte $3C                   ;..####..
L05CE:  .byte $7E                   ;.######.
L05CF:  .byte $66                   ;.##..##.
L05D0:  .byte $66                   ;.##..##.
L05D1:  .byte $66                   ;.##..##.
L05D2:  .byte $7E                   ;.######.
L05D3:  .byte $7E                   ;.######.
L05D4:  .byte $66                   ;.##..##.
L05D5:  .byte $66                   ;.##..##.
L05D6:  .byte $3E                   ;.#####..  'B' (B)
L05D7:  .byte $7E                   ;.######.
L05D8:  .byte $66                   ;.##..##.
L05D9:  .byte $66                   ;.##..##.
L05DA:  .byte $3E                   ;.#####..
L05DB:  .byte $7E                   ;.######.
L05DC:  .byte $66                   ;.##..##.
L05DD:  .byte $66                   ;.##..##.
L05DE:  .byte $7E                   ;.######.
L05DF:  .byte $3E                   ;.#####..
L05E0:  .byte $3C                   ;..####..  'C' (C)
L05E1:  .byte $7E                   ;.######.
L05E2:  .byte $66                   ;.##..##.
L05E3:  .byte $06                   ;.##.....
L05E4:  .byte $06                   ;.##.....
L05E5:  .byte $06                   ;.##.....
L05E6:  .byte $06                   ;.##.....
L05E7:  .byte $66                   ;.##..##.
L05E8:  .byte $7E                   ;.######.
L05E9:  .byte $3C                   ;..####..
L05EA:  .byte $3E                   ;.#####..  'D' (D)
L05EB:  .byte $7E                   ;.######.
L05EC:  .byte $66                   ;.##..##.
L05ED:  .byte $66                   ;.##..##.
L05EE:  .byte $66                   ;.##..##.
L05EF:  .byte $66                   ;.##..##.
L05F0:  .byte $66                   ;.##..##.
L05F1:  .byte $66                   ;.##..##.
L05F2:  .byte $7E                   ;.######.
L05F3:  .byte $3E                   ;.#####..
L05F4:  .byte $7E                   ;.######.  'E' (E)
L05F5:  .byte $7E                   ;.######.
L05F6:  .byte $06                   ;.##.....
L05F7:  .byte $06                   ;.##.....
L05F8:  .byte $3E                   ;.#####..
L05F9:  .byte $3E                   ;.#####..
L05FA:  .byte $06                   ;.##.....
L05FB:  .byte $06                   ;.##.....
L05FC:  .byte $7E                   ;.######.
L05FD:  .byte $7E                   ;.######.
L05FE:  .byte $7E                   ;.######.  'F' (F)
L05FF:  .byte $7E                   ;.######.
L0600:  .byte $06                   ;.##.....
L0601:  .byte $06                   ;.##.....
L0602:  .byte $3E                   ;.#####..
L0603:  .byte $3E                   ;.#####..
L0604:  .byte $06                   ;.##.....
L0605:  .byte $06                   ;.##.....
L0606:  .byte $06                   ;.##.....
L0607:  .byte $06                   ;.##.....
L0608:  .byte $3C                   ;..####..  'G' (G)
L0609:  .byte $7E                   ;.######.
L060A:  .byte $66                   ;.##..##.
L060B:  .byte $06                   ;.##.....
L060C:  .byte $06                   ;.##.....
L060D:  .byte $76                   ;.##.###.
L060E:  .byte $76                   ;.##.###.
L060F:  .byte $66                   ;.##..##.
L0610:  .byte $7E                   ;.######.
L0611:  .byte $3C                   ;..####..
L0612:  .byte $66                   ;.##..##.  'H' (H)
L0613:  .byte $66                   ;.##..##.
L0614:  .byte $66                   ;.##..##.
L0615:  .byte $66                   ;.##..##.
L0616:  .byte $7E                   ;.######.
L0617:  .byte $7E                   ;.######.
L0618:  .byte $66                   ;.##..##.
L0619:  .byte $66                   ;.##..##.
L061A:  .byte $66                   ;.##..##.
L061B:  .byte $66                   ;.##..##.
L061C:  .byte $3C                   ;..####..  'I' (I)
L061D:  .byte $3C                   ;..####..
L061E:  .byte $18                   ;...##...
L061F:  .byte $18                   ;...##...
L0620:  .byte $18                   ;...##...
L0621:  .byte $18                   ;...##...
L0622:  .byte $18                   ;...##...
L0623:  .byte $18                   ;...##...
L0624:  .byte $3C                   ;..####..
L0625:  .byte $3C                   ;..####..
L0626:  .byte $60                   ;.....##.  'J' (J)
L0627:  .byte $60                   ;.....##.
L0628:  .byte $60                   ;.....##.
L0629:  .byte $60                   ;.....##.
L062A:  .byte $60                   ;.....##.
L062B:  .byte $60                   ;.....##.
L062C:  .byte $60                   ;.....##.
L062D:  .byte $66                   ;.##..##.
L062E:  .byte $7E                   ;.######.
L062F:  .byte $3C                   ;..####..
L0630:  .byte $18                   ;...##...  'K' (K, drawn as a down arrow)
L0631:  .byte $18                   ;...##...
L0632:  .byte $18                   ;...##...
L0633:  .byte $18                   ;...##...
L0634:  .byte $18                   ;...##...
L0635:  .byte $99                   ;#..##..#
L0636:  .byte $FF                   ;########
L0637:  .byte $7E                   ;.######.
L0638:  .byte $3C                   ;..####..
L0639:  .byte $18                   ;...##...
L063A:  .byte $06                   ;.##.....  'L' (L)
L063B:  .byte $06                   ;.##.....
L063C:  .byte $06                   ;.##.....
L063D:  .byte $06                   ;.##.....
L063E:  .byte $06                   ;.##.....
L063F:  .byte $06                   ;.##.....
L0640:  .byte $06                   ;.##.....
L0641:  .byte $06                   ;.##.....
L0642:  .byte $7E                   ;.######.
L0643:  .byte $7E                   ;.######.
L0644:  .byte $C3                   ;##....##  'M' (M)
L0645:  .byte $C3                   ;##....##
L0646:  .byte $E7                   ;###..###
L0647:  .byte $E7                   ;###..###
L0648:  .byte $FF                   ;########
L0649:  .byte $FF                   ;########
L064A:  .byte $DB                   ;##.##.##
L064B:  .byte $C3                   ;##....##
L064C:  .byte $C3                   ;##....##
L064D:  .byte $C3                   ;##....##
L064E:  .byte $66                   ;.##..##.  'N' (N)
L064F:  .byte $66                   ;.##..##.
L0650:  .byte $6E                   ;.###.##.
L0651:  .byte $6E                   ;.###.##.
L0652:  .byte $7E                   ;.######.
L0653:  .byte $7E                   ;.######.
L0654:  .byte $76                   ;.##.###.
L0655:  .byte $76                   ;.##.###.
L0656:  .byte $66                   ;.##..##.
L0657:  .byte $66                   ;.##..##.
L0658:  .byte $3C                   ;..####..  'O' (O)
L0659:  .byte $7E                   ;.######.
L065A:  .byte $66                   ;.##..##.
L065B:  .byte $66                   ;.##..##.
L065C:  .byte $66                   ;.##..##.
L065D:  .byte $66                   ;.##..##.
L065E:  .byte $66                   ;.##..##.
L065F:  .byte $66                   ;.##..##.
L0660:  .byte $7E                   ;.######.
L0661:  .byte $3C                   ;..####..
L0662:  .byte $3E                   ;.#####..  'P' (P)
L0663:  .byte $7E                   ;.######.
L0664:  .byte $66                   ;.##..##.
L0665:  .byte $66                   ;.##..##.
L0666:  .byte $7E                   ;.######.
L0667:  .byte $3E                   ;.#####..
L0668:  .byte $06                   ;.##.....
L0669:  .byte $06                   ;.##.....
L066A:  .byte $06                   ;.##.....
L066B:  .byte $06                   ;.##.....
L066C:  .byte $66                   ;.##..##.  'Q' (Q, drawn as Y)
L066D:  .byte $66                   ;.##..##.
L066E:  .byte $7E                   ;.######.
L066F:  .byte $3C                   ;..####..
L0670:  .byte $18                   ;...##...
L0671:  .byte $18                   ;...##...
L0672:  .byte $18                   ;...##...
L0673:  .byte $18                   ;...##...
L0674:  .byte $18                   ;...##...
L0675:  .byte $18                   ;...##...
L0676:  .byte $3E                   ;.#####..  'R' (R)
L0677:  .byte $7E                   ;.######.
L0678:  .byte $66                   ;.##..##.
L0679:  .byte $66                   ;.##..##.
L067A:  .byte $7E                   ;.######.
L067B:  .byte $3E                   ;.#####..
L067C:  .byte $76                   ;.##.###.
L067D:  .byte $66                   ;.##..##.
L067E:  .byte $66                   ;.##..##.
L067F:  .byte $66                   ;.##..##.
L0680:  .byte $3C                   ;..####..  'S' (S)
L0681:  .byte $7E                   ;.######.
L0682:  .byte $66                   ;.##..##.
L0683:  .byte $06                   ;.##.....
L0684:  .byte $3E                   ;.#####..
L0685:  .byte $7C                   ;..#####.
L0686:  .byte $60                   ;.....##.
L0687:  .byte $66                   ;.##..##.
L0688:  .byte $7E                   ;.######.
L0689:  .byte $3C                   ;..####..
L068A:  .byte $7E                   ;.######.  'T' (T)
L068B:  .byte $7E                   ;.######.
L068C:  .byte $18                   ;...##...
L068D:  .byte $18                   ;...##...
L068E:  .byte $18                   ;...##...
L068F:  .byte $18                   ;...##...
L0690:  .byte $18                   ;...##...
L0691:  .byte $18                   ;...##...
L0692:  .byte $18                   ;...##...
L0693:  .byte $18                   ;...##...
L0694:  .byte $66                   ;.##..##.  'U' (U)
L0695:  .byte $66                   ;.##..##.
L0696:  .byte $66                   ;.##..##.
L0697:  .byte $66                   ;.##..##.
L0698:  .byte $66                   ;.##..##.
L0699:  .byte $66                   ;.##..##.
L069A:  .byte $66                   ;.##..##.
L069B:  .byte $66                   ;.##..##.
L069C:  .byte $7E                   ;.######.
L069D:  .byte $3C                   ;..####..
L069E:  .byte $66                   ;.##..##.  'V' (V)
L069F:  .byte $66                   ;.##..##.
L06A0:  .byte $66                   ;.##..##.
L06A1:  .byte $66                   ;.##..##.
L06A2:  .byte $66                   ;.##..##.
L06A3:  .byte $7E                   ;.######.
L06A4:  .byte $3C                   ;..####..
L06A5:  .byte $3C                   ;..####..
L06A6:  .byte $18                   ;...##...
L06A7:  .byte $18                   ;...##...
L06A8:  .byte $C3                   ;##....##  'W' (W)
L06A9:  .byte $C3                   ;##....##
L06AA:  .byte $C3                   ;##....##
L06AB:  .byte $DB                   ;##.##.##
L06AC:  .byte $FF                   ;########
L06AD:  .byte $FF                   ;########
L06AE:  .byte $E7                   ;###..###
L06AF:  .byte $E7                   ;###..###
L06B0:  .byte $C3                   ;##....##
L06B1:  .byte $C3                   ;##....##

;==============================================================================
; Clown objects ($06B2-$0A40)
;   A clown object (CL_ offsets in clowns_defines.asm) remembers where it was
;   drawn so that the next update can take the picture off again: either by
;   blanking its box (CL_STATE b5) or by putting back the background bytes saved
;   while it was drawn (b6).
;==============================================================================

;------------------------------------------------------------------------------
; EraseFlyer - Remove the object's last picture, as its state bits ask.
;   b5: blank the box (BlankBox). Else b6: put the saved background back; a slow
;   object (b4) only does so on every 4th call.
;------------------------------------------------------------------------------
EraseFlyer:
L06B2:  MOV  A,M
L06B3:  ANI  $20                    ;Blank the box?
L06B5:  JZ   RestoreBackground      ;No

;------------------------------------------------------------------------------
; BlankBox - Write zeros over the object's box and clear state b5.
;------------------------------------------------------------------------------
BlankBox:
L06B8:  MOV  A,M
L06B9:  ANI  $DF                    ;Request done
L06BB:  CALL ObjectBox              ;DE = screen address, C = rows, HL -> width
L06BE:  MOV  A,M                    ;Screen bytes per row
L06BF:  XCHG                        ;HL = screen address
L06C0:  DCR  A                      ;Two bytes per row?
L06C1:  DCR  A
L06C2:  MOV  A,C
L06C3:  JNZ  L06D1                  ;No: three
L06C6:  MVI  C,$1F                  ;To the next line: 32 - 1
L06C8:  MOV  M,B
L06C9:  INX  H
L06CA:  MOV  M,B
L06CB:  DAD  B
L06CC:  DCR  A
L06CD:  JNZ  L06C8                  ;Next row
L06D0:  RET
L06D1:  MVI  C,$1E                  ;To the next line: 32 - 2
L06D3:  MOV  M,B
L06D4:  INX  H
L06D5:  MOV  M,B
L06D6:  INX  H
L06D7:  MOV  M,B
L06D8:  DAD  B
L06D9:  DCR  A
L06DA:  JNZ  L06D3                  ;Next row
L06DD:  RET

RestoreBackground:
L06DE:  MOV  A,M
L06DF:  ANI  $40                    ;Put the background back?
L06E1:  RZ                          ;No: nothing to remove
L06E2:  MOV  A,M
L06E3:  ANI  $10                    ;Slow object?
L06E5:  JZ   L06F1                  ;No
L06E8:  INR  M                      ;Count its updates
L06E9:  MOV  A,M
L06EA:  ANI  $03                    ;Every 4th one only
L06EC:  RNZ
L06ED:  MOV  A,M
L06EE:  ANI  $F8                    ;Tick back to 0
L06F0:  MOV  M,A
L06F1:  MOV  A,M
L06F2:  ANI  $BF                    ;Request done
L06F4:  CALL ObjectBox              ;DE = screen address, C = rows
L06F7:  INX  H                      ;HL -> saved bytes
L06F8:  XCHG                        ;HL = screen, DE = saved bytes
L06F9:  LDAX D                      ;Three bytes per row
L06FA:  INX  D
L06FB:  MOV  M,A
L06FC:  INX  H
L06FD:  LDAX D
L06FE:  INX  D
L06FF:  MOV  M,A
L0700:  INX  H
L0701:  LDAX D
L0702:  INX  D
L0703:  MOV  M,A
L0704:  MOV  A,C
L0705:  MVI  C,$1E                  ;To the next line: 32 - 2
L0707:  DAD  B
L0708:  MOV  C,A
L0709:  DCR  C
L070A:  JNZ  L06F9                  ;Next row
L070D:  RET

;------------------------------------------------------------------------------
; ObjectBox - Store A as the object's state; DE = its screen address, C = rows, HL -> width, B = 0.
;------------------------------------------------------------------------------
ObjectBox:
L070E:  MOV  M,A
L070F:  LXI  B,CL_SCREEN
L0712:  DAD  B
L0713:  MOV  E,M
L0714:  INX  H
L0715:  MOV  D,M
L0716:  INX  H
L0717:  MOV  C,M
L0718:  INX  H
L0719:  RET

;------------------------------------------------------------------------------
; EraseRider - Blank the rider's old box if its state asks for it.
;------------------------------------------------------------------------------
EraseRider:
L071A:  MOV  A,M
L071B:  ANI  $20                    ;Only set when it has just landed as the flyer
L071D:  RZ
L071E:  JMP  BlankBox               ;Blank the box

;------------------------------------------------------------------------------
; DrawFlyer - Move the flying clown and draw it.
;   X += XVEL, turning back when the result is $F2 or more (past the right edge,
;   or below 0 at the left); Y += YVEL, turning back when the result is $F0 or
;   more (above the top). The picture CL_FRAME (2 bytes
;   wide) is OR-ed into the screen through the shifter, 3 screen bytes per row;
;   the bytes that were there are saved in the object first, both for
;   RestoreBackground and for CheckContact. ERASE_MODE is OR-ed into the state
;   so that the next update takes the picture off again. A slow object (b4) is
;   only drawn when its tick is 0.
;------------------------------------------------------------------------------
DrawFlyer:
L0721:  MOV  A,M
L0722:  ANA  A
L0723:  RP                          ;Not in use
L0724:  ANI  $10                    ;Slow object?
L0726:  JZ   L072D
L0729:  MOV  A,M
L072A:  ANI  $03                    ;Yes: only on tick 0
L072C:  RNZ
L072D:  LDA  ERASE_MODE             ;How to erase this picture next time
L0730:  ORA  M
L0731:  MOV  M,A
L0732:  INX  H
L0733:  MOV  C,M                    ;C = picture number
L0734:  INX  H
L0735:  MOV  A,M                    ;X velocity
L0736:  INX  H
L0737:  ADD  M                      ;+ X
L0738:  CPI  $F2                    ;Off either edge?
L073A:  JC   L0745                  ;No
L073D:  DCX  H                      ;Yes: reverse the X velocity
L073E:  MOV  A,M
L073F:  CMA
L0740:  INR  A
L0741:  MOV  M,A
L0742:  JMP  L0736                  ;and try again
L0745:  MOV  M,A                    ;New X
L0746:  MOV  E,A
L0747:  ANI  $07                    ;X within the byte
L0749:  OUT  OUT_SHIFT_AMT          ;to the shifter
L074B:  INX  H
L074C:  MOV  A,M                    ;Y velocity
L074D:  INX  H
L074E:  ADD  M                      ;+ Y
L074F:  CPI  $F0                    ;Above the top?
L0751:  JC   L075B                  ;No
L0754:  DCX  H                      ;Yes: reverse the Y velocity
L0755:  MOV  A,M
L0756:  CMA
L0757:  INR  A
L0758:  MOV  M,A
L0759:  INX  H
L075A:  MOV  A,M                    ;and stay at the same Y
L075B:  MOV  M,A                    ;New Y
L075C:  MOV  D,A
L075D:  INX  H
L075E:  CALL ScreenAddr             ;DE = screen address, B = 0
L0761:  MOV  M,E                    ;Remember it for the erase
L0762:  INX  H
L0763:  MOV  M,D
L0764:  INX  H
L0765:  PUSH H
L0766:  LXI  H,ClownPictures        ;Picture pointers
L0769:  DAD  B
L076A:  DAD  B
L076B:  MOV  C,M                    ;BC = picture
L076C:  INX  H
L076D:  MOV  B,M
L076E:  POP  H
L076F:  LDAX B                      ;Rows
L0770:  INX  B
L0771:  PUSH PSW
L0772:  MOV  M,A                    ;CL_ROWS
L0773:  INX  H
L0774:  LDAX B                      ;Picture bytes per row (always 2)
L0775:  INX  B
L0776:  MOV  M,A
L0777:  INR  M                      ;CL_WIDTH: one more on screen
L0778:  INX  H
L0779:  XCHG                        ;HL = screen, DE -> CL_SAVED
L077A:  POP  PSW
L077B:  PUSH PSW
L077C:  MOV  A,M                    ;Save the background byte
L077D:  STAX D
L077E:  INX  D
L077F:  LDAX B                      ;First picture byte
L0780:  INX  B
L0781:  OUT  OUT_SHIFT_DATA
L0783:  IN   INP_SHIFT
L0785:  ORA  M                      ;OR it in
L0786:  MOV  M,A
L0787:  INX  H
L0788:  MOV  A,M                    ;Second background byte
L0789:  STAX D
L078A:  INX  D
L078B:  LDAX B                      ;Second picture byte
L078C:  INX  B
L078D:  OUT  OUT_SHIFT_DATA
L078F:  IN   INP_SHIFT
L0791:  ORA  M
L0792:  MOV  M,A
L0793:  INX  H
L0794:  MOV  A,M                    ;Third background byte
L0795:  STAX D
L0796:  INX  D
L0797:  XRA  A                      ;Flush the shifter:
L0798:  OUT  OUT_SHIFT_DATA
L079A:  IN   INP_SHIFT
L079C:  ORA  M                      ;the spill of the second byte
L079D:  MOV  M,A
L079E:  PUSH B
L079F:  LXI  B,$001E                ;To the next line: 32 - 2
L07A2:  DAD  B
L07A3:  POP  B
L07A4:  POP  PSW
L07A5:  DCR  A
L07A6:  JNZ  L077B                  ;Next row
L07A9:  RET

;------------------------------------------------------------------------------
; DrawRider - Draw the clown that stands on the seesaw.
;   It stands on the low end: at SEESAW_X + $22 when the right end is down, at
;   SEESAW_X otherwise (while the seesaw tips, b5 and b6 both set, it is already
;   drawn on the left). One fixed picture, 8 pixels wide, 15 rows; the
;   background is saved as for the flyer but is never put back - EraseSeesaw
;   blanks the whole area.
;------------------------------------------------------------------------------
DrawRider:
L07AA:  MOV  A,M
L07AB:  ANA  A
L07AC:  RP                          ;Not in use
L07AD:  INX  H
L07AE:  INX  H
L07AF:  INX  H                      ;HL -> CL_X
L07B0:  LDA  SEESAW_STATE
L07B3:  ANI  $60                    ;Right end down and not tipping?
L07B5:  MVI  D,$22                  ;Yes: 34 pixels right of the seesaw's left end
L07B7:  JPO  L07BC                  ;(parity odd = exactly one of b5 b6)
L07BA:  MVI  D,$00                  ;No: at the left end
L07BC:  LDA  SEESAW_X
L07BF:  ADD  D                      ;+ seesaw X
L07C0:  MOV  E,A
L07C1:  ANI  $07                    ;X within the byte
L07C3:  OUT  OUT_SHIFT_AMT          ;to the shifter
L07C5:  MOV  M,E                    ;CL_X
L07C6:  INX  H
L07C7:  MOV  A,M                    ;Y velocity
L07C8:  INX  H
L07C9:  ADD  M                      ;+ Y
L07CA:  MOV  D,A
L07CB:  MOV  M,A                    ;CL_Y
L07CC:  INX  H
L07CD:  CALL ScreenAddr             ;DE = screen address
L07D0:  MOV  M,E                    ;Remember it
L07D1:  INX  H
L07D2:  MOV  M,D
L07D3:  INX  H
L07D4:  MVI  A,$0F                  ;15 rows
L07D6:  MOV  M,A
L07D7:  INX  H
L07D8:  MVI  M,$02                  ;2 screen bytes per row
L07DA:  INX  H
L07DB:  XCHG                        ;HL = screen, DE -> CL_SAVED
L07DC:  LXI  B,RiderPicture
L07DF:  PUSH PSW
L07E0:  MOV  A,M                    ;Save the background byte
L07E1:  STAX D
L07E2:  INX  D
L07E3:  LDAX B                      ;Picture byte
L07E4:  INX  B
L07E5:  OUT  OUT_SHIFT_DATA
L07E7:  IN   INP_SHIFT
L07E9:  ORA  M                      ;OR it in
L07EA:  MOV  M,A
L07EB:  INX  H
L07EC:  MOV  A,M                    ;Second background byte
L07ED:  STAX D
L07EE:  INX  D
L07EF:  XRA  A                      ;Flush the shifter: the spill
L07F0:  OUT  OUT_SHIFT_DATA
L07F2:  IN   INP_SHIFT
L07F4:  ORA  M
L07F5:  MOV  M,A
L07F6:  PUSH B
L07F7:  LXI  B,$001F                ;To the next line: 32 - 1
L07FA:  DAD  B
L07FB:  POP  B
L07FC:  POP  PSW
L07FD:  DCR  A
L07FE:  JNZ  L07DF                  ;Next row
L0801:  RET

;------------------------------------------------------------------------------
; RiderPicture - The standing clown, 15 rows of 1 byte.
;------------------------------------------------------------------------------
RiderPicture:
L0802:  .byte $08                   ;...#....
L0803:  .byte $1C                   ;..###...
L0804:  .byte $1C                   ;..###...
L0805:  .byte $1C                   ;..###...
L0806:  .byte $08                   ;...#....
L0807:  .byte $3E                   ;.#####..
L0808:  .byte $5D                   ;#.###.#.
L0809:  .byte $5D                   ;#.###.#.
L080A:  .byte $3E                   ;.#####..
L080B:  .byte $1C                   ;..###...
L080C:  .byte $1C                   ;..###...
L080D:  .byte $1C                   ;..###...
L080E:  .byte $14                   ;..#.#...
L080F:  .byte $14                   ;..#.#...
L0810:  .byte $36                   ;.##.##..
L0811:  .byte $00                   ;........  (not drawn)

;------------------------------------------------------------------------------
; ClownPictures - Pointers to the 18 flyer pictures (CL_FRAME).
;   $00 standing; $01-$08 tumbling (AnimateFlyer cycles $01-$03, a popped
;   balloon picks $01-$08 at random); $09-$0B walking right and $0C-$0E walking
;   left (serve); $0F-$11 splat. Each picture is rows, bytes per row (2), then
;   the rows.
;------------------------------------------------------------------------------
ClownPictures:
L0812:  .word ClownStand            ;picture $00
L0814:  .word ClownTumble1          ;picture $01
L0816:  .word ClownTumble2          ;picture $02
L0818:  .word ClownTumble3          ;picture $03
L081A:  .word ClownTumble4          ;picture $04
L081C:  .word ClownTumble5          ;picture $05
L081E:  .word ClownTumble6          ;picture $06
L0820:  .word ClownTumble7          ;picture $07
L0822:  .word ClownTumble8          ;picture $08
L0824:  .word ClownWalkR1           ;picture $09
L0826:  .word ClownWalkR2           ;picture $0A
L0828:  .word ClownWalkR3           ;picture $0B
L082A:  .word ClownWalkL1           ;picture $0C
L082C:  .word ClownWalkL2           ;picture $0D
L082E:  .word ClownWalkL3           ;picture $0E
L0830:  .word ClownSplat1           ;picture $0F
L0832:  .word ClownSplat2           ;picture $10
L0834:  .word ClownSplat3           ;picture $11

ClownWalkR1:
L0836:  .byte $10, $02              ;16 rows, 2 bytes wide
L0838:  .byte $40, $00              ;......#.........
L083A:  .byte $E0, $00              ;.....###........
L083C:  .byte $E0, $01              ;.....####.......
L083E:  .byte $E0, $00              ;.....###........
L0840:  .byte $40, $00              ;......#.........
L0842:  .byte $C0, $00              ;......##........
L0844:  .byte $E0, $01              ;.....####.......
L0846:  .byte $D0, $02              ;....#.##.#......
L0848:  .byte $D0, $04              ;....#.##..#.....
L084A:  .byte $D0, $08              ;....#.##...#....
L084C:  .byte $D0, $03              ;....#.####......
L084E:  .byte $40, $02              ;......#..#......
L0850:  .byte $40, $02              ;......#..#......
L0852:  .byte $40, $06              ;......#..##.....
L0854:  .byte $40, $00              ;......#.........
L0856:  .byte $C0, $00              ;......##........

ClownWalkR2:
L0858:  .byte $10, $02              ;16 rows, 2 bytes wide
L085A:  .byte $40, $00              ;......#.........
L085C:  .byte $E0, $00              ;.....###........
L085E:  .byte $E0, $01              ;.....####.......
L0860:  .byte $E0, $00              ;.....###........
L0862:  .byte $40, $00              ;......#.........
L0864:  .byte $C0, $00              ;......##........
L0866:  .byte $E0, $0F              ;.....#######....
L0868:  .byte $D0, $00              ;....#.##........
L086A:  .byte $C8, $00              ;...#..##........
L086C:  .byte $C8, $00              ;...#..##........
L086E:  .byte $48, $00              ;...#..#.........
L0870:  .byte $40, $00              ;......#.........
L0872:  .byte $40, $00              ;......#.........
L0874:  .byte $40, $00              ;......#.........
L0876:  .byte $40, $00              ;......#.........
L0878:  .byte $C0, $01              ;......###.......

ClownWalkR3:
L087A:  .byte $10, $02              ;16 rows, 2 bytes wide
L087C:  .byte $80, $00              ;.......#........
L087E:  .byte $C0, $01              ;......###.......
L0880:  .byte $C0, $03              ;......####......
L0882:  .byte $C0, $01              ;......###.......
L0884:  .byte $80, $00              ;.......#........
L0886:  .byte $C0, $00              ;......##........
L0888:  .byte $E0, $03              ;.....#####......
L088A:  .byte $90, $05              ;....#..##.#.....
L088C:  .byte $88, $09              ;...#...##..#....
L088E:  .byte $84, $11              ;..#....##...#...
L0890:  .byte $C0, $01              ;......###.......
L0892:  .byte $60, $01              ;.....##.#.......
L0894:  .byte $20, $01              ;.....#..#.......
L0896:  .byte $18, $01              ;...##...#.......
L0898:  .byte $08, $01              ;...#....#.......
L089A:  .byte $00, $03              ;........##......

ClownWalkL1:
L089C:  .byte $10, $02              ;16 rows, 2 bytes wide
L089E:  .byte $80, $00              ;.......#........
L08A0:  .byte $C0, $01              ;......###.......
L08A2:  .byte $E0, $01              ;.....####.......
L08A4:  .byte $C0, $01              ;......###.......
L08A6:  .byte $80, $00              ;.......#........
L08A8:  .byte $C0, $00              ;......##........
L08AA:  .byte $E0, $01              ;.....####.......
L08AC:  .byte $D0, $02              ;....#.##.#......
L08AE:  .byte $C8, $02              ;...#..##.#......
L08B0:  .byte $C4, $02              ;..#...##.#......
L08B2:  .byte $F0, $00              ;....####........
L08B4:  .byte $90, $00              ;....#..#........
L08B6:  .byte $90, $00              ;....#..#........
L08B8:  .byte $98, $00              ;...##..#........
L08BA:  .byte $80, $00              ;.......#........
L08BC:  .byte $C0, $00              ;......##........

ClownWalkL2:
L08BE:  .byte $10, $02              ;16 rows, 2 bytes wide
L08C0:  .byte $40, $00              ;......#.........
L08C2:  .byte $E0, $00              ;.....###........
L08C4:  .byte $F0, $00              ;....####........
L08C6:  .byte $E0, $00              ;.....###........
L08C8:  .byte $40, $00              ;......#.........
L08CA:  .byte $60, $00              ;.....##.........
L08CC:  .byte $FE, $00              ;.#######........
L08CE:  .byte $60, $01              ;.....##.#.......
L08D0:  .byte $60, $02              ;.....##..#......
L08D2:  .byte $60, $02              ;.....##..#......
L08D4:  .byte $40, $02              ;......#..#......
L08D6:  .byte $40, $00              ;......#.........
L08D8:  .byte $40, $00              ;......#.........
L08DA:  .byte $40, $00              ;......#.........
L08DC:  .byte $40, $00              ;......#.........
L08DE:  .byte $60, $00              ;.....##.........

ClownWalkL3:
L08E0:  .byte $10, $02              ;16 rows, 2 bytes wide
L08E2:  .byte $80, $00              ;.......#........
L08E4:  .byte $C0, $01              ;......###.......
L08E6:  .byte $E0, $01              ;.....####.......
L08E8:  .byte $C0, $01              ;......###.......
L08EA:  .byte $80, $00              ;.......#........
L08EC:  .byte $C0, $00              ;......##........
L08EE:  .byte $E0, $03              ;.....#####......
L08F0:  .byte $D0, $04              ;....#.##..#.....
L08F2:  .byte $C8, $08              ;...#..##...#....
L08F4:  .byte $C4, $10              ;..#...##....#...
L08F6:  .byte $C0, $01              ;......###.......
L08F8:  .byte $40, $03              ;......#.##......
L08FA:  .byte $40, $02              ;......#..#......
L08FC:  .byte $40, $0C              ;......#...##....
L08FE:  .byte $40, $08              ;......#....#....
L0900:  .byte $60, $00              ;.....##.........

ClownTumble1:
L0902:  .byte $10, $02              ;16 rows, 2 bytes wide
L0904:  .byte $00, $01              ;........#.......
L0906:  .byte $80, $03              ;.......###......
L0908:  .byte $84, $03              ;..#....###......
L090A:  .byte $88, $03              ;...#...###......
L090C:  .byte $10, $01              ;....#...#.......
L090E:  .byte $E0, $07              ;.....######.....
L0910:  .byte $80, $0B              ;.......###.#....
L0912:  .byte $80, $13              ;.......###..#...
L0914:  .byte $80, $23              ;.......###...#..
L0916:  .byte $80, $03              ;.......###......
L0918:  .byte $E0, $03              ;.....#####......
L091A:  .byte $30, $06              ;....##...##.....
L091C:  .byte $18, $04              ;...##.....#.....
L091E:  .byte $0C, $04              ;..##......#.....
L0920:  .byte $00, $04              ;..........#.....
L0922:  .byte $00, $0C              ;..........##....

ClownTumble2:
L0924:  .byte $0E, $02              ;14 rows, 2 bytes wide
L0926:  .byte $00, $01              ;........#.......
L0928:  .byte $80, $03              ;.......###......
L092A:  .byte $84, $43              ;..#....###....#.
L092C:  .byte $88, $23              ;...#...###...#..
L092E:  .byte $10, $11              ;....#...#...#...
L0930:  .byte $E0, $0F              ;.....#######....
L0932:  .byte $80, $03              ;.......###......
L0934:  .byte $80, $03              ;.......###......
L0936:  .byte $80, $03              ;.......###......
L0938:  .byte $80, $03              ;.......###......
L093A:  .byte $C0, $07              ;......#####.....
L093C:  .byte $60, $0C              ;.....##...##....
L093E:  .byte $30, $18              ;....##.....##...
L0940:  .byte $18, $30              ;...##.......##..

ClownTumble3:
L0942:  .byte $0F, $02              ;15 rows, 2 bytes wide
L0944:  .byte $80, $00              ;.......#........
L0946:  .byte $C0, $01              ;......###.......
L0948:  .byte $C0, $21              ;......###....#..
L094A:  .byte $C0, $11              ;......###...#...
L094C:  .byte $80, $08              ;.......#...#....
L094E:  .byte $E0, $07              ;.....######.....
L0950:  .byte $D0, $01              ;....#.###.......
L0952:  .byte $C8, $01              ;...#..###.......
L0954:  .byte $C4, $01              ;..#...###.......
L0956:  .byte $C0, $01              ;......###.......
L0958:  .byte $E0, $03              ;.....#####......
L095A:  .byte $60, $06              ;.....##..##.....
L095C:  .byte $60, $0C              ;.....##...##....
L095E:  .byte $20, $18              ;.....#.....##...
L0960:  .byte $30, $00              ;....##..........

ClownTumble4:
L0962:  .byte $0C, $02              ;12 rows, 2 bytes wide
L0964:  .byte $00, $40              ;..............#.
L0966:  .byte $00, $20              ;.............#..
L0968:  .byte $00, $10              ;............#...
L096A:  .byte $01, $08              ;#..........#....
L096C:  .byte $07, $04              ;###.......#.....
L096E:  .byte $3C, $04              ;..####....#.....
L0970:  .byte $E0, $77              ;.....######.###.
L0972:  .byte $E0, $FF              ;.....###########
L0974:  .byte $E0, $77              ;.....######.###.
L0976:  .byte $38, $04              ;...###....#.....
L0978:  .byte $1F, $FC              ;#####.....######
L097A:  .byte $01, $00              ;#...............

ClownTumble5:
L097C:  .byte $0B, $02              ;11 rows, 2 bytes wide
L097E:  .byte $04, $00              ;..#.............
L0980:  .byte $08, $00              ;...#............
L0982:  .byte $10, $80              ;....#..........#
L0984:  .byte $20, $E0              ;.....#.......###
L0986:  .byte $20, $3C              ;.....#....####..
L0988:  .byte $EE, $07              ;.###.######.....
L098A:  .byte $FF, $07              ;###########.....
L098C:  .byte $EE, $07              ;.###.######.....
L098E:  .byte $20, $1C              ;.....#....###...
L0990:  .byte $3F, $F8              ;######.....#####
L0992:  .byte $00, $80              ;...............#

ClownTumble6:
L0994:  .byte $10, $02              ;16 rows, 2 bytes wide
L0996:  .byte $30, $00              ;....##..........
L0998:  .byte $20, $00              ;.....#..........
L099A:  .byte $20, $30              ;.....#......##..
L099C:  .byte $20, $18              ;.....#.....##...
L099E:  .byte $60, $0C              ;.....##...##....
L09A0:  .byte $C0, $07              ;......#####.....
L09A2:  .byte $C0, $01              ;......###.......
L09A4:  .byte $C4, $01              ;..#...###.......
L09A6:  .byte $C8, $01              ;...#..###.......
L09A8:  .byte $D0, $01              ;....#.###.......
L09AA:  .byte $E0, $07              ;.....######.....
L09AC:  .byte $80, $08              ;.......#...#....
L09AE:  .byte $C0, $11              ;......###...#...
L09B0:  .byte $C0, $21              ;......###....#..
L09B2:  .byte $C0, $01              ;......###.......
L09B4:  .byte $80, $00              ;.......#........

ClownTumble7:
L09B6:  .byte $0E, $02              ;14 rows, 2 bytes wide
L09B8:  .byte $0C, $18              ;..##.......##...
L09BA:  .byte $18, $0C              ;...##.....##....
L09BC:  .byte $30, $06              ;....##...##.....
L09BE:  .byte $E0, $03              ;.....#####......
L09C0:  .byte $C0, $01              ;......###.......
L09C2:  .byte $C0, $01              ;......###.......
L09C4:  .byte $C0, $01              ;......###.......
L09C6:  .byte $C0, $01              ;......###.......
L09C8:  .byte $F0, $07              ;....#######.....
L09CA:  .byte $88, $08              ;...#...#...#....
L09CC:  .byte $C4, $11              ;..#...###...#...
L09CE:  .byte $C2, $21              ;.#....###....#..
L09D0:  .byte $C0, $01              ;......###.......
L09D2:  .byte $80, $00              ;.......#........

ClownTumble8:
L09D4:  .byte $0F, $02              ;15 rows, 2 bytes wide
L09D6:  .byte $00, $0C              ;..........##....
L09D8:  .byte $18, $04              ;...##.....#.....
L09DA:  .byte $30, $06              ;....##...##.....
L09DC:  .byte $60, $06              ;.....##..##.....
L09DE:  .byte $C0, $07              ;......#####.....
L09E0:  .byte $80, $03              ;.......###......
L09E2:  .byte $80, $23              ;.......###...#..
L09E4:  .byte $80, $13              ;.......###..#...
L09E6:  .byte $80, $0B              ;.......###.#....
L09E8:  .byte $E0, $07              ;.....######.....
L09EA:  .byte $10, $01              ;....#...#.......
L09EC:  .byte $88, $03              ;...#...###......
L09EE:  .byte $84, $03              ;..#....###......
L09F0:  .byte $80, $03              ;.......###......
L09F2:  .byte $00, $01              ;........#.......

ClownStand:
L09F4:  .byte $0F, $02              ;15 rows, 2 bytes wide
L09F6:  .byte $00, $01              ;........#.......
L09F8:  .byte $80, $03              ;.......###......
L09FA:  .byte $80, $03              ;.......###......
L09FC:  .byte $80, $03              ;.......###......
L09FE:  .byte $00, $01              ;........#.......
L0A00:  .byte $C0, $07              ;......#####.....
L0A02:  .byte $A0, $0B              ;.....#.###.#....
L0A04:  .byte $A0, $0B              ;.....#.###.#....
L0A06:  .byte $C0, $07              ;......#####.....
L0A08:  .byte $80, $03              ;.......###......
L0A0A:  .byte $80, $03              ;.......###......
L0A0C:  .byte $80, $03              ;.......###......
L0A0E:  .byte $80, $02              ;.......#.#......
L0A10:  .byte $80, $02              ;.......#.#......
L0A12:  .byte $C0, $06              ;......##.##.....

ClownSplat1:
L0A14:  .byte $0A, $02              ;10 rows, 2 bytes wide
L0A16:  .byte $00, $01              ;........#.......
L0A18:  .byte $80, $03              ;.......###......
L0A1A:  .byte $84, $43              ;..#....###....#.
L0A1C:  .byte $88, $23              ;...#...###...#..
L0A1E:  .byte $10, $11              ;....#...#...#...
L0A20:  .byte $E0, $0F              ;.....#######....
L0A22:  .byte $80, $03              ;.......###......
L0A24:  .byte $80, $03              ;.......###......
L0A26:  .byte $84, $43              ;..#....###....#.
L0A28:  .byte $FC, $7F              ;..#############.

ClownSplat2:
L0A2A:  .byte $06, $02              ;6 rows, 2 bytes wide
L0A2C:  .byte $00, $01              ;........#.......
L0A2E:  .byte $80, $03              ;.......###......
L0A30:  .byte $80, $03              ;.......###......
L0A32:  .byte $84, $43              ;..#....###....#.
L0A34:  .byte $2C, $69              ;..##.#..#..#.##.
L0A36:  .byte $FC, $7F              ;..#############.

ClownSplat3:
L0A38:  .byte $03, $02              ;3 rows, 2 bytes wide
L0A3A:  .byte $08, $03              ;...#....##......
L0A3C:  .byte $DC, $47              ;..###.#####...#.
L0A3E:  .byte $FC, $7F              ;..#############.
L0A40:  .byte $00                   ;unused

;==============================================================================
; SECTION 4  Main loop and its tasks ($0A41-$0DF3)
;   The foreground: a small script interpreter that sequences attract mode and
;   the game, and - whenever the script waits - one pass over the game tasks.
;   The tasks only change variables and draw text; the interrupts draw the
;   moving objects.
;==============================================================================

;------------------------------------------------------------------------------
; GameStart - Normal power-on: clear all RAM and start the script at AttractScript.
;------------------------------------------------------------------------------
GameStart:
L0A41:  XRA  A                      ;Tone and sounds off
L0A42:  OUT  OUT_TONE_LO
L0A44:  OUT  OUT_TONE_HI
L0A46:  OUT  OUT_SOUND
L0A48:  CALL ClearRamTop            ;A = 0: all 256 blocks, $2000-$3FFF
L0A4B:  LXI  H,AttractScript        ;Script starts with attract mode
L0A4E:  SHLD SCRIPT_PTR

;------------------------------------------------------------------------------
; MainLoop - Run script commands until a WAIT, then one pass of the game tasks.
;   The script byte at SCRIPT_PTR is an even opcode 2-$20 that indexes
;   ScriptOps; the handler gets the address of its arguments in DE and returns
;   here (this routine's address is pushed first). Opcode 0 is WAIT: the pointer
;   stays on it and the tasks below run every pass until a timer event moves the
;   script on (ScriptTimerDone, CheckTimeout). Interrupts are off while commands
;   run and back on at a WAIT.
;------------------------------------------------------------------------------
MainLoop:
L0A51:  LXI  H,MainLoop             ;Every path returns to MainLoop
L0A54:  PUSH H
L0A55:  OUT  OUT_WATCHDOG
L0A57:  LHLD SCRIPT_PTR
L0A5A:  MOV  A,M                    ;Script opcode
L0A5B:  ANA  A
L0A5C:  JZ   L0A71                  ;0 = WAIT: run the game tasks
L0A5F:  DI                          ;No interrupts while the script changes things
L0A60:  INX  H
L0A61:  SHLD SCRIPT_PTR             ;Step past the opcode
L0A64:  XCHG                        ;DE -> arguments
L0A65:  LXI  H,ScriptOps-2          ;Opcodes start at 2
L0A68:  MOV  C,A
L0A69:  MVI  B,$00
L0A6B:  DAD  B                      ;+ opcode
L0A6C:  MOV  A,M
L0A6D:  INX  H
L0A6E:  MOV  H,M
L0A6F:  MOV  L,A
L0A70:  PCHL                        ;To the handler
;WAIT: one pass of the game tasks
L0A71:  EI
L0A72:  CALL HandleContact          ;Act on what the flyer touched
L0A75:  CALL FormatScores           ;Scores to text, one character to the screen
L0A78:  CALL RunTimerEvents         ;Expired timers
L0A7B:  CALL RunTimerEvents2
L0A7E:  CALL CheckTimeout           ;Script timeout
L0A81:  CALL ServeClown             ;New jump wanted?
L0A84:  CALL AnimateFlyer           ;Flyer picture and erase mode
L0A87:  CALL DrawNextDigit          ;Another score character
L0A8A:  CALL HandleContact          ;Contact again: it must not wait a whole pass
L0A8D:  CALL DrawNextDigit          ;Another score character
L0A90:  CALL ReadStartButtons
L0A93:  CALL DrawPlayfieldIfOn      ;Floor and ledges
L0A96:  CALL Autopilot              ;Attract mode steers the seesaw
L0A99:  LDA  GAME_ACTIVE            ;Game on?
L0A9C:  ANA  A
L0A9D:  RZ                          ;No
L0A9E:  CALL DrawNextDigit
L0AA1:  CALL CheckRowsCleared       ;A balloon row emptied?
L0AA4:  RET                         ;Back to MainLoop

;------------------------------------------------------------------------------
; Random - Next 8-bit pseudo-random number in A (and RNG_SEED).
;   Shift register: the seed moves right one bit and the parity of its bits 0, 2,
;   3 and 4 comes in at the top. A zero seed is replaced by $FF first.
;------------------------------------------------------------------------------
Random:
L0AA5:  LXI  H,RNG_SEED
L0AA8:  MVI  C,$00
L0AAA:  MOV  A,M
L0AAB:  ANA  A
L0AAC:  JNZ  L0AB0                  ;Seed 0 would stay 0
L0AAF:  DCR  A
L0AB0:  MOV  B,A
L0AB1:  ANI  $1D                    ;Taps: bits 0, 2, 3, 4
L0AB3:  JPE  L0AB8                  ;Even parity: shift in 0
L0AB6:  MVI  C,$80                  ;Odd: shift in 1
L0AB8:  MOV  A,B
L0AB9:  RRC                         ;Seed >> 1
L0ABA:  ANI  $7F
L0ABC:  ADD  C
L0ABD:  MOV  M,A                    ;New seed
L0ABE:  RET

;------------------------------------------------------------------------------
; BalloonTasks - The six odd-frame balloon passes: first balloon, routine.
;   A pass moves every other balloon of one row by one pixel, so each balloon
;   moves once in 12 frames. Top and bottom rows drift right, the middle row left.
;------------------------------------------------------------------------------
BalloonTasks:
L0ABF:  .word P1_ROW_TOP, MoveBalloonsRight ;phase 0: even balloons of the top row move right
L0AC3:  .word P1_ROW_MID, MoveBalloonsLeft ;phase 1: even balloons of the middle row move left
L0AC7:  .word P1_ROW_BOT, MoveBalloonsRight ;phase 2: even balloons of the bottom row move right
L0ACB:  .word P1_ROW_TOP+3, MoveBalloonsRight ;phase 3: odd balloons of the top row move right
L0ACF:  .word P1_ROW_MID+3, MoveBalloonsLeft ;phase 4: odd balloons of the middle row move left
L0AD3:  .word P1_ROW_BOT+3, MoveBalloonsRight ;phase 5: odd balloons of the bottom row move right

;------------------------------------------------------------------------------
; AnimateFlyer - Choose the flyer's picture and erase mode from its height.
;   Not while it is being served. Y $B0-$BB (coming down on the seesaw): stand
;   upright, blank-box erase. Above $B0: erase by restoring the background, and
;   from $54 down tumble through pictures 1-3, one step every 7 ticks. In the
;   balloon rows (above $54) the picture is left alone.
;------------------------------------------------------------------------------
AnimateFlyer:
L0AD7:  LDA  SERVING                ;Walking on its ledge?
L0ADA:  ANA  A
L0ADB:  RNZ
L0ADC:  LHLD FLYER_PTR              ;The flyer
L0ADF:  MOV  A,M
L0AE0:  ANA  A
L0AE1:  RP                          ;Not in use
L0AE2:  MOV  D,H                    ;DE = the object
L0AE3:  MOV  E,L
L0AE4:  LXI  B,CL_Y
L0AE7:  DAD  B
L0AE8:  MOV  A,M                    ;Its Y
L0AE9:  CPI  $BC                    ;Down at the seesaw already
L0AEB:  RNC
L0AEC:  CPI  $B0                    ;Just above the seesaw?
L0AEE:  JC   L0AFA                  ;No: higher up
L0AF1:  MVI  A,$20                  ;Erase by blanking the box
L0AF3:  STA  ERASE_MODE
L0AF6:  INX  D                      ;CL_FRAME
L0AF7:  XRA  A
L0AF8:  STAX D                      ;Picture 0: standing
L0AF9:  RET
L0AFA:  CPI  $54                    ;In the balloon rows?
L0AFC:  MVI  A,$40                  ;Higher than the seesaw: erase by restoring the background
L0AFE:  STA  ERASE_MODE
L0B01:  RC                          ;Yes: keep the picture
L0B02:  LXI  H,TMR_TUMBLE           ;Time for the next tumble picture?
L0B05:  MOV  A,M
L0B06:  ANA  A
L0B07:  RNZ
L0B08:  MVI  M,$07                  ;Every 7 ticks
L0B0A:  INX  D                      ;CL_FRAME
L0B0B:  LDAX D
L0B0C:  INR  A
L0B0D:  CPI  $04                    ;Pictures 1, 2, 3, 1 ...
L0B0F:  JC   L0B14
L0B12:  MVI  A,$01
L0B14:  STAX D
L0B15:  RET
L0B16:  .byte $00                   ;unused

;------------------------------------------------------------------------------
; MoveBalloonsRight - Move six balloons (every other one from DE) one pixel right and redraw them.
;------------------------------------------------------------------------------
MoveBalloonsRight:
L0B17:  CALL PlayerRow              ;HL = first balloon, in the current player's rows
L0B1A:  MVI  A,$06                  ;Six balloons
L0B1C:  PUSH PSW
L0B1D:  MOV  A,M                    ;State
L0B1E:  ANA  A
L0B1F:  JP   L0B38                  ;Popped
L0B22:  PUSH H
L0B23:  INX  H
L0B24:  INR  M                      ;X + 1
L0B25:  MOV  A,M
L0B26:  MOV  E,A
L0B27:  ANI  $07                    ;X within the byte
L0B29:  OUT  OUT_SHIFT_AMT          ;to the shifter
L0B2B:  INX  H
L0B2C:  MOV  D,M                    ;Y
L0B2D:  CALL ScreenAddr             ;DE = screen address
L0B30:  XCHG                        ;HL = screen address
L0B31:  LXI  D,BalloonRightPic      ;Picture with a blank column on the left
L0B34:  CALL DrawBalloon
L0B37:  POP  H
L0B38:  LXI  D,$0006                ;Skip one balloon
L0B3B:  DAD  D
L0B3C:  POP  PSW
L0B3D:  DCR  A
L0B3E:  JNZ  L0B1C
L0B41:  RET

;------------------------------------------------------------------------------
; MoveBalloonsLeft - Move six balloons (every other one from DE) one pixel left and redraw them.
;------------------------------------------------------------------------------
MoveBalloonsLeft:
L0B42:  CALL PlayerRow
L0B45:  MVI  A,$06
L0B47:  PUSH PSW
L0B48:  MOV  A,M
L0B49:  ANA  A
L0B4A:  JP   L0B63                  ;Popped
L0B4D:  PUSH H
L0B4E:  INX  H
L0B4F:  DCR  M                      ;X - 1
L0B50:  MOV  A,M
L0B51:  MOV  E,A
L0B52:  ANI  $07
L0B54:  OUT  OUT_SHIFT_AMT
L0B56:  INX  H
L0B57:  MOV  D,M
L0B58:  CALL ScreenAddr
L0B5B:  XCHG
L0B5C:  LXI  D,BalloonLeftPic       ;Picture with a blank column on the right
L0B5F:  CALL DrawBalloon
L0B62:  POP  H
L0B63:  LXI  D,$0006                ;Skip one balloon
L0B66:  DAD  D
L0B67:  POP  PSW
L0B68:  DCR  A
L0B69:  JNZ  L0B47
L0B6C:  RET

;------------------------------------------------------------------------------
; PlayerRow - HL = balloon address DE, moved to player 2's rows when PLAYER is 2. DE = P2_OFFSET.
;------------------------------------------------------------------------------
PlayerRow:
L0B6D:  XCHG
L0B6E:  LDA  PLAYER
L0B71:  LXI  D,P2_OFFSET
L0B74:  ANA  A
L0B75:  RZ                          ;Player 1
L0B76:  DAD  D
L0B77:  RET

;------------------------------------------------------------------------------
; DrawBalloon - Draw the 8-row balloon picture DE at screen address HL through the shifter.
;   Overwrites two screen bytes per row. The blank column on the trailing side
;   of each picture wipes the column the balloon has just left.
;------------------------------------------------------------------------------
DrawBalloon:
L0B78:  MVI  B,$08
L0B7A:  LDAX D
L0B7B:  INX  D
L0B7C:  OUT  OUT_SHIFT_DATA         ;Picture byte, shifted
L0B7E:  IN   INP_SHIFT
L0B80:  MOV  M,A
L0B81:  INX  H
L0B82:  XRA  A                      ;Flush the shifter: the spill
L0B83:  OUT  OUT_SHIFT_DATA
L0B85:  IN   INP_SHIFT
L0B87:  MOV  M,A
L0B88:  MOV  A,B
L0B89:  LXI  B,$001F                ;To the next line: 32 - 1
L0B8C:  DAD  B
L0B8D:  MOV  B,A
L0B8E:  DCR  B
L0B8F:  JNZ  L0B7A                  ;Next row
L0B92:  RET

;------------------------------------------------------------------------------
; BalloonRightPic - Balloon as drawn in the rows that move right.
;------------------------------------------------------------------------------
BalloonRightPic:
L0B93:  .byte $38                   ;...###..
L0B94:  .byte $7C                   ;..#####.
L0B95:  .byte $FE                   ;.#######
L0B96:  .byte $BE                   ;.#####.#
L0B97:  .byte $9E                   ;.####..#
L0B98:  .byte $4C                   ;..##..#.
L0B99:  .byte $38                   ;...###..
L0B9A:  .byte $00                   ;........

;------------------------------------------------------------------------------
; BalloonLeftPic - Balloon as drawn in the row that moves left.
;------------------------------------------------------------------------------
BalloonLeftPic:
L0B9B:  .byte $00                   ;........
L0B9C:  .byte $1C                   ;..###...
L0B9D:  .byte $3E                   ;.#####..
L0B9E:  .byte $7F                   ;#######.
L0B9F:  .byte $5F                   ;#####.#.
L0BA0:  .byte $4F                   ;####..#.
L0BA1:  .byte $26                   ;.##..#..
L0BA2:  .byte $1C                   ;..###...
L0BA3:  .byte $00                   ;unused

;------------------------------------------------------------------------------
; ServeClown - Start a new jump when SERVE_REQUEST is set.
;   One clown object becomes the rider, standing on the seesaw at Y $C4. The
;   other becomes the flyer and starts on one of the four ledges, picked at
;   random from ServeTable: it walks (slow object) toward the middle until
;   TMR_SERVE_JUMP makes it jump off one second later.
;------------------------------------------------------------------------------
ServeClown:
L0BA4:  LXI  H,SERVE_REQUEST
L0BA7:  MOV  A,M                    ;Requested?
L0BA8:  ANA  A
L0BA9:  RZ
L0BAA:  MVI  M,$00                  ;Once
L0BAC:  CALL Random
L0BAF:  ANI  $03                    ;1-4
L0BB1:  INR  A
L0BB2:  LXI  H,ServeTable-6         ;Entry 1 is at ServeTable
L0BB5:  LXI  B,$0006                ;6 bytes per entry
L0BB8:  DAD  B
L0BB9:  DCR  A
L0BBA:  JNZ  L0BB8
L0BBD:  PUSH H                      ;The ledge's entry
L0BBE:  LDA  PLAYER                 ;Which player? (only swaps the two objects)
L0BC1:  ANA  A
L0BC2:  LXI  H,CLOWN_A
L0BC5:  LXI  D,CLOWN_B
L0BC8:  JNZ  L0BCC
L0BCB:  XCHG
L0BCC:  XCHG                        ;HL = rider object, DE = flyer object
L0BCD:  MVI  M,$80                  ;Rider: in use
L0BCF:  PUSH H
L0BD0:  DAD  B                      ;-> CL_Y
L0BD1:  DCX  H
L0BD2:  MVI  M,$C4                  ;Standing on the seesaw
L0BD4:  POP  H
L0BD5:  SHLD RIDER_PTR
L0BD8:  XCHG
L0BD9:  DAD  B                      ;HL -> past the flyer's first six bytes
L0BDA:  POP  D
L0BDB:  LDAX D                      ;Copy the entry backwards:
L0BDC:  INX  D
L0BDD:  DCX  H
L0BDE:  MOV  M,A                    ;Y, YVEL, X, XVEL, FRAME, STATE
L0BDF:  DCR  C
L0BE0:  JNZ  L0BDB
L0BE3:  SHLD FLYER_PTR
L0BE6:  MVI  A,$01                  ;Walk animation starts
L0BE8:  STA  TMR_WALK
L0BEB:  STA  SERVING                ;No gravity or tumbling yet
L0BEE:  MVI  A,$1E                  ;Jump off after 30 ticks
L0BF0:  STA  TMR_SERVE_JUMP
L0BF3:  RET

;------------------------------------------------------------------------------
; ServeTable - Flyer start values for the four ledges: CL_Y down to CL_STATE.
;------------------------------------------------------------------------------
ServeTable:
L0BF4:  .byte $68, $00, $00, $01, $09, $90 ;Y=$68 YVEL=0 X=$00 XVEL=1 FRAME=$09 STATE=$90: upper left ledge
L0BFA:  .byte $88, $00, $00, $01, $09, $90 ;Y=$88 YVEL=0 X=$00 XVEL=1 FRAME=$09 STATE=$90: lower left ledge
L0C00:  .byte $68, $00, $F0, $FF, $0C, $90 ;Y=$68 YVEL=0 X=$F0 XVEL=-1 FRAME=$0C STATE=$90: upper right ledge
L0C06:  .byte $88, $00, $F0, $FF, $0C, $90 ;Y=$88 YVEL=0 X=$F0 XVEL=-1 FRAME=$0C STATE=$90: lower right ledge
L0C0C:  .byte $00                   ;unused

;------------------------------------------------------------------------------
; FormatScores - In a game: write both scores and the jumps left into TEXT_BUF.
;   Falls into DrawNextDigit.
;------------------------------------------------------------------------------
FormatScores:
L0C0D:  LDA  GAME_ACTIVE
L0C10:  ANA  A
L0C11:  RZ                          ;Attract mode: the script draws the scores
L0C12:  LXI  H,TEXT_BUF
L0C15:  LXI  B,P1_SCORE
L0C18:  CALL FormatScore            ;Player 1 score: 5 characters
L0C1B:  LDAX B                      ;Jumps left
L0C1C:  INX  B
L0C1D:  CALL NibbleToChar           ;as a digit
L0C20:  MOV  M,A
L0C21:  INX  H
L0C22:  CALL FormatScore            ;Player 2 score

;------------------------------------------------------------------------------
; DrawNextDigit - In a game: draw the next character of TEXT_BUF at its place on the score line.
;   One character per call (three calls per main loop pass). Six characters in a
;   one-player game, eleven with two players.
;------------------------------------------------------------------------------
DrawNextDigit:
L0C25:  LDA  GAME_ACTIVE
L0C28:  ANA  A
L0C29:  RZ                          ;Attract mode
L0C2A:  LDA  TWO_PLAYERS
L0C2D:  ANA  A
L0C2E:  MVI  B,$06                  ;Player 1 score and jumps left
L0C30:  JZ   L0C35
L0C33:  MVI  B,$0B                  ;Two players: the second score as well
L0C35:  LXI  H,DIGIT_INDEX
L0C38:  MOV  A,M
L0C39:  INR  A
L0C3A:  CMP  B                      ;Past the last one?
L0C3B:  JC   L0C3F
L0C3E:  XRA  A                      ;Start again
L0C3F:  MOV  M,A
L0C40:  MOV  C,A
L0C41:  MVI  B,$00
L0C43:  LXI  H,ScoreLineAddrs       ;Screen address of this character
L0C46:  DAD  B
L0C47:  DAD  B
L0C48:  MOV  E,M
L0C49:  INX  H
L0C4A:  MOV  D,M
L0C4B:  LXI  H,TEXT_BUF             ;HL -> the character
L0C4E:  DAD  B
L0C4F:  MVI  A,$01                  ;One character
L0C51:  JMP  DrawString

;------------------------------------------------------------------------------
; BcdToChars - Write the BCD byte at BC as two digit characters at HL.
;------------------------------------------------------------------------------
BcdToChars:
L0C54:  LDAX B
L0C55:  CALL HighNibbleToChar       ;High digit
L0C58:  MOV  M,A
L0C59:  INX  H
L0C5A:  LDAX B
L0C5B:  INX  B
L0C5C:  CALL NibbleToChar           ;Low digit
L0C5F:  MOV  M,A
L0C60:  INX  H
L0C61:  RET

;------------------------------------------------------------------------------
; FormatScore - Write the 2-byte BCD score at BC as 5 characters at HL.
;   Four digits with leading zeros turned into blanks ('@'), then the fixed
;   final '0': scores count tens of points.
;------------------------------------------------------------------------------
FormatScore:
L0C62:  MOV  D,H                    ;DE = start of the text
L0C63:  MOV  E,L
L0C64:  CALL BcdToChars
L0C67:  CALL BcdToChars
L0C6A:  XCHG                        ;From the start:
L0C6B:  CALL BlankZeros             ;blank the leading zeros
L0C6E:  XCHG
L0C6F:  MVI  M,$30                  ;The units digit is always 0
L0C71:  INX  H
L0C72:  RET

;------------------------------------------------------------------------------
; HighNibbleToChar - A = character for the high nibble of A.
;------------------------------------------------------------------------------
HighNibbleToChar:
L0C73:  RRC
L0C74:  RRC
L0C75:  RRC
L0C76:  RRC

;------------------------------------------------------------------------------
; NibbleToChar - A = character '0'-'9' ('A'-'F') for the low nibble of A.
;------------------------------------------------------------------------------
NibbleToChar:
L0C77:  ANI  $0F
L0C79:  ADI  $90                    ;The usual 8080 hex-to-ASCII trick
L0C7B:  DAA
L0C7C:  ACI  $40
L0C7E:  DAA
L0C7F:  RET

;------------------------------------------------------------------------------
; BlankZeros - Replace '0' characters from HL by blanks, up to the first other character.
;------------------------------------------------------------------------------
BlankZeros:
L0C80:  MOV  A,M
L0C81:  CPI  $30
L0C83:  RNZ                         ;Not a zero: done
L0C84:  MVI  M,$40                  ;'@' is the blank
L0C86:  INX  H
L0C87:  JMP  BlankZeros

;------------------------------------------------------------------------------
; ScoreLineAddrs - Screen address for each character of TEXT_BUF.
;------------------------------------------------------------------------------
ScoreLineAddrs:
L0C8A:  .word $2598                 ;player 1 score (col 24, line 12)
L0C8C:  .word $2599                 ;player 1 score (col 25, line 12)
L0C8E:  .word $259A                 ;player 1 score (col 26, line 12)
L0C90:  .word $259B                 ;player 1 score (col 27, line 12)
L0C92:  .word $259C                 ;player 1 score (col 28, line 12)
L0C94:  .word $2590                 ;jumps left (col 16, line 12)
L0C96:  .word $2583                 ;player 2 score (col 3, line 12)
L0C98:  .word $2584                 ;player 2 score (col 4, line 12)
L0C9A:  .word $2585                 ;player 2 score (col 5, line 12)
L0C9C:  .word $2586                 ;player 2 score (col 6, line 12)
L0C9E:  .word $2587                 ;player 2 score (col 7, line 12)

;------------------------------------------------------------------------------
; ReadStartButtons - Read the two start buttons (twice, for a stable reading).
;------------------------------------------------------------------------------
ReadStartButtons:
L0CA0:  IN   INP_SWITCH
L0CA2:  MOV  B,A
L0CA3:  IN   INP_SWITCH
L0CA5:  CMP  B                      ;The same both times?
L0CA6:  RNZ                         ;No: keep the old state
L0CA7:  CMA                         ;Active low
L0CA8:  ANI  $20                    ;b5: 1-player start
L0CAA:  STA  START1_DOWN
L0CAD:  MOV  A,B
L0CAE:  CMA
L0CAF:  ANI  $10                    ;b4: 2-player start
L0CB1:  STA  START2_DOWN
L0CB4:  RET

;------------------------------------------------------------------------------
; DrawPlayfieldIfOn - Redraw the floor and ledges when PLAYFIELD_ON.
;------------------------------------------------------------------------------
DrawPlayfieldIfOn:
L0CB5:  LDA  PLAYFIELD_ON
L0CB8:  ANA  A
L0CB9:  RZ

;------------------------------------------------------------------------------
; DrawPlayfield - Draw the floor line and the four ledges.
;------------------------------------------------------------------------------
DrawPlayfield:
L0CBA:  LXI  H,$3E80                ;Line 212, column 0
L0CBD:  LXI  B,$20FF                ;B = 32 bytes, C = solid
L0CC0:  CALL FillRun                ;The floor, full width
L0CC3:  LXI  H,$3700                ;Line 152, left
L0CC6:  MVI  B,$04                  ;32 pixels
L0CC8:  CALL FillRun
L0CCB:  LXI  H,$371C                ;Line 152, right
L0CCE:  MVI  B,$04
L0CD0:  CALL FillRun
L0CD3:  LXI  H,$3300                ;Line 120, left
L0CD6:  CALL FillRun3               ;24 pixels
L0CD9:  LXI  H,$331D                ;Line 120, right

FillRun3:
L0CDC:  MVI  B,$03

;------------------------------------------------------------------------------
; FillRun - Write C to B bytes from HL.
;------------------------------------------------------------------------------
FillRun:
L0CDE:  MOV  M,C
L0CDF:  INX  H
L0CE0:  DCR  B
L0CE1:  JNZ  FillRun
L0CE4:  RET

;------------------------------------------------------------------------------
; Autopilot - Attract mode: put the seesaw under the falling clown.
;   PADDLE_POS = flyer X - 4 when the right end is down, X - 24 when the left
;   end is down, so that the flyer comes down on the raised end. If that is
;   not within 0-$DF, the seesaw goes to the end of the floor on the flyer's
;   half of the screen.
;------------------------------------------------------------------------------
Autopilot:
L0CE5:  LDA  AUTOPILOT
L0CE8:  ANA  A
L0CE9:  RZ                          ;Only in attract mode
L0CEA:  LDA  TMR_HIT_LOCKOUT        ;Just launched: leave the seesaw
L0CED:  ANA  A
L0CEE:  RNZ
L0CEF:  LHLD FLYER_PTR
L0CF2:  MOV  A,M
L0CF3:  ANA  A
L0CF4:  RP                          ;Flyer not in use
L0CF5:  INX  H                      ;HL -> CL_X
L0CF6:  INX  H
L0CF7:  INX  H
L0CF8:  MOV  B,M                    ;B = X
L0CF9:  LDA  SEESAW_STATE
L0CFC:  ANI  $20                    ;Which end is down?
L0CFE:  MVI  A,$FC                  ;Right end: 4 left of the flyer
L0D00:  JNZ  L0D05
L0D03:  MVI  A,$E8                  ;Left end: 24 left of the flyer
L0D05:  ADD  M
L0D06:  CPI  $E0                    ;Within 0-$DF?
L0D08:  JC   L0D12                  ;Yes
L0D0B:  INR  B                      ;Flyer in the right half?
L0D0C:  MVI  A,$D7                  ;Yes: far right
L0D0E:  JM   L0D12
L0D11:  XRA  A                      ;No: far left
L0D12:  STA  PADDLE_POS
L0D15:  RET

;------------------------------------------------------------------------------
; CheckRowsCleared - In a game: award the bonus when the player empties a balloon row.
;   INP_DIP b4 off (each row): the first empty row among top, middle, bottom
;   scores its RowBonusTable value and is refilled 5 seconds later. b4 on (all
;   rows): nothing until all three are empty, then 2000 points and all three
;   are refilled. Either way BONUS and the value are shown, the bonus tune
;   plays and flyer and balloons freeze for 3 seconds.
;------------------------------------------------------------------------------
CheckRowsCleared:
L0D16:  LDA  REFILL_PENDING         ;A refill already on its way?
L0D19:  ANA  A
L0D1A:  RNZ
L0D1B:  LDA  PLAYER                 ;Which player's rows?
L0D1E:  ANA  A
L0D1F:  LXI  H,P1_ROW_TOP
L0D22:  LXI  D,P2_OFFSET
L0D25:  JZ   L0D29
L0D28:  DAD  D
L0D29:  IN   INP_DIP                ;Balloon resets switch
L0D2B:  ANI  $10
L0D2D:  JNZ  CheckAllRowsCleared    ;All rows
L0D30:  MVI  C,$02                  ;Three rows: C = 2, 1, 0
L0D32:  PUSH H
L0D33:  MVI  B,$0C                  ;12 balloons
L0D35:  MOV  A,M
L0D36:  ANA  A
L0D37:  JM   L0D8E                  ;One left: try the next row
L0D3A:  INX  H
L0D3B:  INX  H
L0D3C:  INX  H
L0D3D:  DCR  B
L0D3E:  JNZ  L0D35
L0D41:  POP  H                      ;Empty row
L0D42:  SHLD REFILL_ROW_PTR         ;Remember which, for the refill
L0D45:  LXI  H,RowBonusTable        ;Bonus table: C = 2 is the top row
L0D48:  DAD  B
L0D49:  DAD  B
L0D4A:  DAD  B
L0D4B:  MOV  A,M                    ;Row's Y: marks the refill as pending
L0D4C:  INX  H

AwardRowBonus:
L0D4D:  STA  REFILL_PENDING
L0D50:  MVI  A,$96                  ;Refill in 150 ticks (5 s)
L0D52:  STA  TMR_REFILL
L0D55:  MVI  A,$5A                  ;Freeze for 90 ticks (3 s)
L0D57:  STA  TMR_FREEZE
L0D5A:  STA  FREEZE_REQ
L0D5D:  PUSH H
L0D5E:  MOV  B,M                    ;BC = points, high byte first
L0D5F:  INX  H
L0D60:  MOV  C,M
L0D61:  CALL AddScore               ;Add them
L0D64:  POP  B                      ;BC -> the points again
L0D65:  LXI  H,BONUS_BUF
L0D68:  PUSH H
L0D69:  CALL FormatScore            ;as 5 characters in BONUS_BUF
L0D6C:  LXI  H,BonusTune            ;Bonus tune
L0D6F:  SHLD TUNE_PTR
L0D72:  LXI  H,TxtBonus             ;"BONUS" in big letters
L0D75:  LXI  D,$3486                ;Line 132, column 6
L0D78:  MVI  A,$05
L0D7A:  CALL DrawBigString
L0D7D:  POP  H
L0D7E:  LXI  D,$388D                ;The value on line 164, column 13
L0D81:  IN   INP_DIP
L0D83:  ANI  $10                    ;Each-row values have a leading blank:
L0D85:  JNZ  L0D89
L0D88:  DCX  D                      ;one column left
L0D89:  MVI  A,$05
L0D8B:  JMP  DrawString             ;Draw the 5 characters
L0D8E:  POP  H                      ;Next row of this player: 2 x 36 bytes on
L0D8F:  DAD  D
L0D90:  DAD  D
L0D91:  DCR  C
L0D92:  JP   L0D32                  ;Three rows
L0D95:  RET

CheckAllRowsCleared:
L0D96:  SHLD REFILL_ROW_PTR         ;Refill starts at the top row
L0D99:  MVI  C,$03                  ;Three rows
L0D9B:  MVI  B,$0C
L0D9D:  MOV  A,M
L0D9E:  ANA  A
L0D9F:  RM                          ;A balloon left: no bonus yet
L0DA0:  INX  H
L0DA1:  INX  H
L0DA2:  INX  H
L0DA3:  DCR  B
L0DA4:  JNZ  L0D9D
L0DA7:  DAD  D                      ;Skip the other player's row
L0DA8:  DCR  C
L0DA9:  JNZ  L0D9B
L0DAC:  LXI  H,AllRowsBonus         ;All three empty: 2000 points
L0DAF:  INR  A                      ;A = 1: refill pending
L0DB0:  JMP  AwardRowBonus

;------------------------------------------------------------------------------
; AllRowsBonus - Points for emptying all three rows (BCD, high byte first; in tens).
;------------------------------------------------------------------------------
AllRowsBonus:
L0DB3:  .byte $02, $00              ;all rows cleared: 2000 points

;------------------------------------------------------------------------------
; RowBonusTable - Bonus per row: balloon Y, points high, points low.
;------------------------------------------------------------------------------
RowBonusTable:
L0DB5:  .byte $4E, $00, $20         ;bottom row (Y $4E) cleared: 200 points
L0DB8:  .byte $38, $00, $50         ;middle row (Y $38) cleared: 500 points
L0DBB:  .byte $24, $01, $00         ;top row (Y $24) cleared: 1000 points
L0DBE:  .byte $00                   ;unused

;------------------------------------------------------------------------------
; BonusTune - Played with every bonus (row cleared, extra jump).
;------------------------------------------------------------------------------
BonusTune:
L0DBF:  .byte $85                   ;tempo: 5 frames per beat
L0DC0:  .byte $01, $00              ;1 beat of note $00 (rest)
L0DC2:  .byte $01, $0C              ;1 beat of note $0C
L0DC4:  .byte $02, $0F              ;2 beats of note $0F
L0DC6:  .byte $01, $0C              ;1 beat of note $0C
L0DC8:  .byte $01, $0D              ;1 beat of note $0D
L0DCA:  .byte $02, $0F              ;2 beats of note $0F
L0DCC:  .byte $01, $00              ;1 beat of note $00 (rest)
L0DCE:  .byte $01, $0C              ;1 beat of note $0C
L0DD0:  .byte $02, $0F              ;2 beats of note $0F
L0DD2:  .byte $01, $0C              ;1 beat of note $0C
L0DD4:  .byte $01, $0D              ;1 beat of note $0D
L0DD6:  .byte $03, $0F              ;3 beats of note $0F
L0DD8:  .byte $00                   ;end of tune

;------------------------------------------------------------------------------
; GameOverTune - Played when the game ends.
;------------------------------------------------------------------------------
GameOverTune:
L0DD9:  .byte $85                   ;tempo: 5 frames per beat
L0DDA:  .byte $02, $08              ;2 beats of note $08
L0DDC:  .byte $02, $0D              ;2 beats of note $0D
L0DDE:  .byte $02, $0F              ;2 beats of note $0F
L0DE0:  .byte $02, $12              ;2 beats of note $12
L0DE2:  .byte $08, $11              ;8 beats of note $11
L0DE4:  .byte $02, $08              ;2 beats of note $08
L0DE6:  .byte $02, $0D              ;2 beats of note $0D
L0DE8:  .byte $02, $0F              ;2 beats of note $0F
L0DEA:  .byte $01, $12              ;1 beat of note $12
L0DEC:  .byte $01, $11              ;1 beat of note $11
L0DEE:  .byte $01, $0F              ;1 beat of note $0F
L0DF0:  .byte $07, $11              ;7 beats of note $11
L0DF2:  .byte $00                   ;end of tune
L0DF3:  .byte $00                   ;unused

;==============================================================================
; SECTION 5  Game script and text ($0DF4-$117A)
;   The program that MainLoop interprets. Commands (opcode, arguments):
;   $00 WAIT                        run the game tasks until a timer moves the script on
;   $02 TEXT    n, text, screen     DrawString
;   $04 DELAY   n                   TMR_SCRIPT = n ticks (30 Hz); its expiry steps past the next WAIT
;   $06 TIMEOUT n, addr             TMR_TIMEOUT = n seconds; its expiry jumps to addr
;   $08 GOTO    addr
;   $0A SET     value, addr         store a byte
;   $0C CLEAR   n                   zero n x 32 bytes below $4000 (ClearRamTop)
;   $0E SCORE   score, screen       draw a 2-byte BCD score as 5 characters
;   $10 BIGTEXT n, text, screen     DrawBigString
;   $12 IFZ     addr, target        jump if the byte is 0
;   $14 IFNZ    addr, target        jump if the byte is not 0
;   $16 COINSTART                   if a coin is in: take it and jump by coinage (CoinageScripts)
;   $18 ROW     y, addr             fill a balloon row
;   $1A DECCOIN / $1C INCCOIN       COINS - 1 / + 1
;   $1E TONE / $20 QUIET            steady tone on / tone and sounds off
;   In the text, '@' is the blank, 'Q' prints as Y and 'K' as a down arrow; the
;   comments show the text as it appears.
;==============================================================================

;------------------------------------------------------------------------------
; AttractScript - Entry after power-on and after a game: 2 seconds, then the title screen.
;------------------------------------------------------------------------------
AttractScript:
L0DF4:  .byte $0A, $00, <GAME_ACTIVE, >GAME_ACTIVE ;SET GAME_ACTIVE = $00
L0DF8:  .byte $02, $01, <TxtZero, >TxtZero, $90, $25 ;TEXT "0" at col 16, line 12
L0DFE:  .byte $04, $3C              ;DELAY 60 ticks
L0E00:  .byte $00                   ;WAIT

;------------------------------------------------------------------------------
; ScrTitle - GAME OVER and the high score for 7 seconds.
;------------------------------------------------------------------------------
ScrTitle:
L0E01:  .byte $0C, $FE              ;CLEAR $2040-$3FFF
L0E03:  .byte $0A, $01, <SCRIPT_HOLD, >SCRIPT_HOLD ;SET SCRIPT_HOLD = $01  Only the timeout moves on from the WAIT below
L0E07:  .byte $06, $07, <ScrDemo, >ScrDemo ;TIMEOUT 7 s -> ScrDemo
L0E0B:  .byte $02, $0A, <TxtPlayerOneUp, >TxtPlayerOneUp, $16, $24 ;TEXT "PLAYER ONE" at col 22, line 0
L0E11:  .byte $02, $0A, <TxtPlayerTwo, >TxtPlayerTwo, $00, $24 ;TEXT "PLAYER TWO" at col 0, line 0
L0E17:  .byte $0E, <P1_SCORE, >P1_SCORE, $97, $25 ;SCORE P1_SCORE at col 23, line 12
L0E1C:  .byte $0E, <P2_SCORE, >P2_SCORE, $83, $25 ;SCORE P2_SCORE at col 3, line 12
L0E21:  .byte $10, $04, <TxtGame, >TxtGame, $08, $30 ;BIGTEXT "GAME" at col 8, line 96
L0E27:  .byte $10, $04, <TxtOver, >TxtOver, $08, $35 ;BIGTEXT "OVER" at col 8, line 136
L0E2D:  .byte $02, $0A, <TxtHighScore, >TxtHighScore, $0B, $3A ;TEXT "HIGH SCORE" at col 11, line 176
L0E33:  .byte $0E, <HI_SCORE, >HI_SCORE, $0D, $3C ;SCORE HI_SCORE at col 13, line 192
L0E38:  .byte $00                   ;WAIT

;------------------------------------------------------------------------------
; ScrDemo - Attract demo: one clown, autopilot. Restarts after 45 seconds or 1 second after a splat.
;------------------------------------------------------------------------------
ScrDemo:
L0E39:  .byte $20                   ;QUIET
L0E3A:  .byte $16                   ;COINSTART  A coin starts a game
L0E3B:  .byte $0A, $00, <TUNE_ON, >TUNE_ON ;SET TUNE_ON = $00
L0E3F:  .byte $0A, $00, <SPEED_LEVEL, >SPEED_LEVEL ;SET SPEED_LEVEL = $00
L0E43:  .byte $06, $2D, <ScrDemo, >ScrDemo ;TIMEOUT 45 s -> ScrDemo
L0E47:  .byte $0C, $FE              ;CLEAR $2040-$3FFF
L0E49:  .byte $02, $0A, <TxtPlayerOneUp, >TxtPlayerOneUp, $16, $24 ;TEXT "PLAYER ONE" at col 22, line 0
L0E4F:  .byte $02, $0A, <TxtPlayerTwo, >TxtPlayerTwo, $00, $24 ;TEXT "PLAYER TWO" at col 0, line 0
L0E55:  .byte $0E, <P1_SCORE, >P1_SCORE, $97, $25 ;SCORE P1_SCORE at col 23, line 12
L0E5A:  .byte $0E, <P2_SCORE, >P2_SCORE, $83, $25 ;SCORE P2_SCORE at col 3, line 12
L0E5F:  .byte $02, $0A, <TxtHighScore, >TxtHighScore, $86, $3E ;TEXT "HIGH SCORE" at col 6, line 212
L0E65:  .byte $0E, <HI_SCORE, >HI_SCORE, $80, $3E ;SCORE HI_SCORE at col 0, line 212
L0E6A:  .byte $02, $0D, <TxtInsertCoin, >TxtInsertCoin, $93, $3E ;TEXT "v INSERT COIN" at col 19, line 212  Down arrow + INSERT COIN
L0E70:  .byte $18, $24, <P1_ROW_TOP, >P1_ROW_TOP ;ROW P1_ROW_TOP Y=$24
L0E74:  .byte $18, $38, <P1_ROW_MID, >P1_ROW_MID ;ROW P1_ROW_MID Y=$38
L0E78:  .byte $18, $4E, <P1_ROW_BOT, >P1_ROW_BOT ;ROW P1_ROW_BOT Y=$4E
L0E7C:  .byte $0A, $01, <SERVE_REQUEST, >SERVE_REQUEST ;SET SERVE_REQUEST = $01  Serve a clown
L0E80:  .byte $0A, $A0, <SEESAW_STATE, >SEESAW_STATE ;SET SEESAW_STATE = $A0
L0E84:  .byte $0A, $C0, <ERASE_MODE, >ERASE_MODE ;SET ERASE_MODE = $C0  Erase by restoring the background
L0E88:  .byte $0A, $05, <GRAVITY_PERIOD, >GRAVITY_PERIOD ;SET GRAVITY_PERIOD = $05  Gravity every 5 ticks
L0E8C:  .byte $0A, $01, <PLAYFIELD_ON, >PLAYFIELD_ON ;SET PLAYFIELD_ON = $01
L0E90:  .byte $0A, $01, <AUTOPILOT, >AUTOPILOT ;SET AUTOPILOT = $01

ScrDemoLoop:
L0E94:  .byte $20                   ;QUIET
L0E95:  .byte $16                   ;COINSTART
L0E96:  .byte $04, $05              ;DELAY 5 ticks
L0E98:  .byte $00                   ;WAIT
L0E99:  .byte $08, <ScrDemoLoop, >ScrDemoLoop ;GOTO ScrDemoLoop

;------------------------------------------------------------------------------
; ScrCoin1C1P - Coinage 0: one coin, one player. A second coin buys the two-player game.
;------------------------------------------------------------------------------
ScrCoin1C1P:
L0E9C:  .byte $0C, $FE              ;CLEAR $2040-$3FFF
L0E9E:  .byte $02, $0D, <TxtToStartGame, >TxtToStartGame, $09, $30 ;TEXT "TO START GAME" at col 9, line 96
L0EA4:  .byte $02, $17, <TxtPressOnePlayerButton, >TxtPressOnePlayerButton, $04, $32 ;TEXT "PRESS ONE PLAYER BUTTON" at col 4, line 112
L0EAA:  .byte $02, $02, <TxtOr, >TxtOr, $0F, $35 ;TEXT "OR" at col 15, line 136
L0EB0:  .byte $02, $10, <TxtDeposit2ndCoin, >TxtDeposit2ndCoin, $08, $38 ;TEXT "DEPOSIT 2ND COIN" at col 8, line 160
L0EB6:  .byte $02, $11, <TxtFor2PlayerGame, >TxtFor2PlayerGame, $07, $3A ;TEXT "FOR 2 PLAYER GAME" at col 7, line 176
L0EBC:  .byte $0A, $01, <COINS_PER_GAME, >COINS_PER_GAME ;SET COINS_PER_GAME = $01
L0EC0:  .byte $14, <START1_DOWN, >START1_DOWN, <ScrNewGame, >ScrNewGame ;IFNZ START1_DOWN GOTO ScrNewGame
L0EC5:  .byte $14, <COINS, >COINS, <ScrSecondCoin, >ScrSecondCoin ;IFNZ COINS GOTO ScrSecondCoin
L0ECA:  .byte $04, $05              ;DELAY 5 ticks
L0ECC:  .byte $00                   ;WAIT
L0ECD:  .byte $08, <L0EC0, >L0EC0   ;GOTO L0EC0

ScrSecondCoin:
L0ED0:  .byte $0C, $FE              ;CLEAR $2040-$3FFF
L0ED2:  .byte $02, $09, <TxtPressTwo, >TxtPressTwo, $04, $30 ;TEXT "PRESS TWO" at col 4, line 96
L0ED8:  .byte $02, $0D, <TxtPlayerButton, >TxtPlayerButton, $0E, $30 ;TEXT "PLAYER BUTTON" at col 14, line 96
L0EDE:  .byte $02, $0D, <TxtToStartGame, >TxtToStartGame, $09, $33 ;TEXT "TO START GAME" at col 9, line 120
L0EE4:  .byte $0A, $02, <COINS_PER_GAME, >COINS_PER_GAME ;SET COINS_PER_GAME = $02
L0EE8:  .byte $14, <START2_DOWN, >START2_DOWN, <ScrTwoPlayersPaid, >ScrTwoPlayersPaid ;IFNZ START2_DOWN GOTO ScrTwoPlayersPaid
L0EED:  .byte $04, $05              ;DELAY 5 ticks
L0EEF:  .byte $00                   ;WAIT
L0EF0:  .byte $08, <L0EE8, >L0EE8   ;GOTO L0EE8

;------------------------------------------------------------------------------
; ScrCoin1C2P - Coinage 1: one coin, one or two players.
;------------------------------------------------------------------------------
ScrCoin1C2P:
L0EF3:  .byte $0C, $FE              ;CLEAR $2040-$3FFF
L0EF5:  .byte $0A, $01, <COINS_PER_GAME, >COINS_PER_GAME ;SET COINS_PER_GAME = $01

ScrEitherButton:
L0EF9:  .byte $14, <START1_DOWN, >START1_DOWN, <ScrNewGame, >ScrNewGame ;IFNZ START1_DOWN GOTO ScrNewGame
L0EFE:  .byte $14, <START2_DOWN, >START2_DOWN, <ScrTwoPlayers, >ScrTwoPlayers ;IFNZ START2_DOWN GOTO ScrTwoPlayers
L0F03:  .byte $04, $05              ;DELAY 5 ticks
L0F05:  .byte $00                   ;WAIT
L0F06:  .byte $08, <ScrEitherButton, >ScrEitherButton ;GOTO ScrEitherButton

;------------------------------------------------------------------------------
; ScrCoin2C2P - Coinage 2: two coins, one or two players. Waits for the second coin.
;------------------------------------------------------------------------------
ScrCoin2C2P:
L0F09:  .byte $0C, $FE              ;CLEAR $2040-$3FFF
L0F0B:  .byte $14, <COINS, >COINS, <L0F16, >L0F16 ;IFNZ COINS GOTO L0F16
L0F10:  .byte $04, $05              ;DELAY 5 ticks
L0F12:  .byte $00                   ;WAIT
L0F13:  .byte $08, <L0F0B, >L0F0B   ;GOTO L0F0B
L0F16:  .byte $1A                   ;DECCOIN
L0F17:  .byte $0A, $02, <COINS_PER_GAME, >COINS_PER_GAME ;SET COINS_PER_GAME = $02
L0F1B:  .byte $0C, $FE              ;CLEAR $2040-$3FFF
L0F1D:  .byte $08, <ScrEitherButton, >ScrEitherButton ;GOTO ScrEitherButton

;------------------------------------------------------------------------------
; ScrCoin2C1P - Coinage 3: two coins per player.
;   After the second coin the 1-player button starts a game. A third coin is
;   taken while waiting, and a fourth allows the 2-player button; coins taken
;   but not needed are given back when the 1-player button is pressed.
;------------------------------------------------------------------------------
ScrCoin2C1P:
L0F20:  .byte $0C, $FE              ;CLEAR $2040-$3FFF
L0F22:  .byte $14, <COINS, >COINS, <L0F2D, >L0F2D ;IFNZ COINS GOTO L0F2D
L0F27:  .byte $04, $05              ;DELAY 5 ticks
L0F29:  .byte $00                   ;WAIT
L0F2A:  .byte $08, <L0F22, >L0F22   ;GOTO L0F22
L0F2D:  .byte $0C, $FE              ;CLEAR $2040-$3FFF
L0F2F:  .byte $1A                   ;DECCOIN
L0F30:  .byte $0A, $02, <COINS_PER_GAME, >COINS_PER_GAME ;SET COINS_PER_GAME = $02
L0F34:  .byte $14, <START1_DOWN, >START1_DOWN, <ScrNewGame, >ScrNewGame ;IFNZ START1_DOWN GOTO ScrNewGame
L0F39:  .byte $14, <COINS, >COINS, <L0F44, >L0F44 ;IFNZ COINS GOTO L0F44
L0F3E:  .byte $04, $05              ;DELAY 5 ticks
L0F40:  .byte $00                   ;WAIT
L0F41:  .byte $08, <L0F34, >L0F34   ;GOTO L0F34
L0F44:  .byte $1A                   ;DECCOIN
L0F45:  .byte $14, <COINS, >COINS, <L0F55, >L0F55 ;IFNZ COINS GOTO L0F55
L0F4A:  .byte $14, <START1_DOWN, >START1_DOWN, <L0F66, >L0F66 ;IFNZ START1_DOWN GOTO L0F66
L0F4F:  .byte $04, $05              ;DELAY 5 ticks
L0F51:  .byte $00                   ;WAIT
L0F52:  .byte $08, <L0F45, >L0F45   ;GOTO L0F45
L0F55:  .byte $1A                   ;DECCOIN
L0F56:  .byte $14, <START2_DOWN, >START2_DOWN, <L0F77, >L0F77 ;IFNZ START2_DOWN GOTO L0F77
L0F5B:  .byte $14, <START1_DOWN, >START1_DOWN, <L0F6E, >L0F6E ;IFNZ START1_DOWN GOTO L0F6E
L0F60:  .byte $04, $05              ;DELAY 5 ticks
L0F62:  .byte $00                   ;WAIT
L0F63:  .byte $08, <L0F56, >L0F56   ;GOTO L0F56
L0F66:  .byte $0A, $01, <COINS_PER_GAME, >COINS_PER_GAME ;SET COINS_PER_GAME = $01
L0F6A:  .byte $1C                   ;INCCOIN
L0F6B:  .byte $08, <ScrNewGame, >ScrNewGame ;GOTO ScrNewGame
L0F6E:  .byte $0A, $02, <COINS_PER_GAME, >COINS_PER_GAME ;SET COINS_PER_GAME = $02
L0F72:  .byte $1C                   ;INCCOIN
L0F73:  .byte $1C                   ;INCCOIN
L0F74:  .byte $08, <ScrNewGame, >ScrNewGame ;GOTO ScrNewGame
L0F77:  .byte $0A, $04, <COINS_PER_GAME, >COINS_PER_GAME ;SET COINS_PER_GAME = $04
L0F7B:  .byte $08, <ScrTwoPlayers, >ScrTwoPlayers ;GOTO ScrTwoPlayers

ScrTwoPlayersPaid:
L0F7E:  .byte $1A                   ;DECCOIN

ScrTwoPlayers:
L0F7F:  .byte $0A, $01, <TWO_PLAYERS, >TWO_PLAYERS ;SET TWO_PLAYERS = $01

;------------------------------------------------------------------------------
; ScrNewGame - Start of a game: fill all six balloon rows, zero the scores.
;------------------------------------------------------------------------------
ScrNewGame:
L0F83:  .byte $18, $24, <P1_ROW_TOP, >P1_ROW_TOP ;ROW P1_ROW_TOP Y=$24
L0F87:  .byte $18, $38, <P1_ROW_MID, >P1_ROW_MID ;ROW P1_ROW_MID Y=$38
L0F8B:  .byte $18, $4E, <P1_ROW_BOT, >P1_ROW_BOT ;ROW P1_ROW_BOT Y=$4E
L0F8F:  .byte $18, $24, <P2_ROW_TOP, >P2_ROW_TOP ;ROW P2_ROW_TOP Y=$24
L0F93:  .byte $18, $38, <P2_ROW_MID, >P2_ROW_MID ;ROW P2_ROW_MID Y=$38
L0F97:  .byte $18, $4E, <P2_ROW_BOT, >P2_ROW_BOT ;ROW P2_ROW_BOT Y=$4E
L0F9B:  .byte $0A, $00, <P1_SCORE, >P1_SCORE ;SET P1_SCORE = $00
L0F9F:  .byte $0A, $00, <[P1_SCORE+1], >[P1_SCORE+1] ;SET P1_SCORE+1 = $00
L0FA3:  .byte $0A, $00, <P2_SCORE, >P2_SCORE ;SET P2_SCORE = $00
L0FA7:  .byte $0A, $00, <[P2_SCORE+1], >[P2_SCORE+1] ;SET P2_SCORE+1 = $00
L0FAB:  .byte $0A, $01, <GAME_ACTIVE, >GAME_ACTIVE ;SET GAME_ACTIVE = $01
L0FAF:  .byte $0A, $A0, <SEESAW_STATE, >SEESAW_STATE ;SET SEESAW_STATE = $A0

;------------------------------------------------------------------------------
; ScrTurn - Start of every jump: clear the screen and clown objects, announce the player.
;   The CLEAR keeps everything below $2180 (balloon rows, flags) and brings in
;   PLAYER and JUMPS_LEFT for this turn. An extra jump shows SAME PLAYER /
;   JUMPS AGAIN instead of GET READY. The down arrow marks the side of the
;   player who is up: column 31 for player 1, column 0 for player 2.
;------------------------------------------------------------------------------
ScrTurn:
L0FB3:  .byte $0C, $F4              ;CLEAR $2180-$3FFF
L0FB5:  .byte $0A, $01, <PADDLE_ENABLE, >PADDLE_ENABLE ;SET PADDLE_ENABLE = $01
L0FB9:  .byte $0A, $01, <PLAYFIELD_ON, >PLAYFIELD_ON ;SET PLAYFIELD_ON = $01
L0FBD:  .byte $0A, $00, <TUNE_ON, >TUNE_ON ;SET TUNE_ON = $00
L0FC1:  .byte $02, $0A, <TxtPlayerOneUp, >TxtPlayerOneUp, $16, $24 ;TEXT "PLAYER ONE" at col 22, line 0
L0FC7:  .byte $02, $05, <TxtJumpsAgain, >TxtJumpsAgain, $0E, $24 ;TEXT "JUMPS" at col 14, line 0
L0FCD:  .byte $12, <TWO_PLAYERS, >TWO_PLAYERS, <L0FD8, >L0FD8 ;IFZ TWO_PLAYERS GOTO L0FD8
L0FD2:  .byte $02, $0A, <TxtPlayerTwo, >TxtPlayerTwo, $00, $24 ;TEXT "PLAYER TWO" at col 0, line 0
L0FD8:  .byte $12, <JUMPS_AGAIN, >JUMPS_AGAIN, <ScrGetReady, >ScrGetReady ;IFZ JUMPS_AGAIN GOTO ScrGetReady
L0FDD:  .byte $1E                   ;TONE
L0FDE:  .byte $10, $04, <TxtSame, >TxtSame, $08, $32 ;BIGTEXT "SAME" at col 8, line 112
L0FE4:  .byte $10, $06, <TxtPlayerJumpsAgain, >TxtPlayerJumpsAgain, $04, $36 ;BIGTEXT "PLAYER" at col 4, line 144
L0FEA:  .byte $02, $01, <TxtInsertCoin, >TxtInsertCoin, $9F, $3E ;TEXT "v" at col 31, line 212
L0FF0:  .byte $12, <PLAYER, >PLAYER, <ScrReadyWait, >ScrReadyWait ;IFZ PLAYER GOTO ScrReadyWait
L0FF5:  .byte $02, $01, <TxtBlanks, >TxtBlanks, $9F, $3E ;TEXT " " at col 31, line 212
L0FFB:  .byte $02, $01, <TxtInsertCoin, >TxtInsertCoin, $80, $3E ;TEXT "v" at col 0, line 212
L1001:  .byte $08, <ScrGo, >ScrGo   ;GOTO ScrGo

ScrGetReady:
L1004:  .byte $02, $09, <TxtGetReady, >TxtGetReady, $0B, $32 ;TEXT "GET READY" at col 11, line 112
L100A:  .byte $02, $01, <TxtInsertCoin, >TxtInsertCoin, $9F, $3E ;TEXT "v" at col 31, line 212
L1010:  .byte $12, <TWO_PLAYERS, >TWO_PLAYERS, <ScrReadyWait, >ScrReadyWait ;IFZ TWO_PLAYERS GOTO ScrReadyWait
L1015:  .byte $02, $0D, <TxtPlayerOneUp, >TxtPlayerOneUp, $0A, $32 ;TEXT "PLAYER ONE UP" at col 10, line 112
L101B:  .byte $12, <PLAYER, >PLAYER, <ScrReadyWait, >ScrReadyWait ;IFZ PLAYER GOTO ScrReadyWait
L1020:  .byte $02, $01, <TxtBlanks, >TxtBlanks, $9F, $3E ;TEXT " " at col 31, line 212
L1026:  .byte $02, $03, <TxtTwo, >TxtTwo, $11, $32 ;TEXT "TWO" at col 17, line 112
L102C:  .byte $02, $01, <TxtInsertCoin, >TxtInsertCoin, $80, $3E ;TEXT "v" at col 0, line 212

ScrReadyWait:
L1032:  .byte $06, $03, <ScrGo, >ScrGo ;TIMEOUT 3 s -> ScrGo
L1036:  .byte $12, <JUMPS_AGAIN, >JUMPS_AGAIN, <L1041, >L1041 ;IFZ JUMPS_AGAIN GOTO L1041
L103B:  .byte $02, $0B, <TxtJumpsAgain, >TxtJumpsAgain, $8A, $3E ;TEXT "JUMPS AGAIN" at col 10, line 212
L1041:  .byte $04, $07              ;DELAY 7 ticks
L1043:  .byte $00                   ;WAIT
L1044:  .byte $02, $0B, <TxtBlanks, >TxtBlanks, $8A, $3E ;TEXT "           " at col 10, line 212
L104A:  .byte $04, $07              ;DELAY 7 ticks
L104C:  .byte $00                   ;WAIT
L104D:  .byte $08, <L1036, >L1036   ;GOTO L1036

;------------------------------------------------------------------------------
; ScrGo - GO: serve the clown, clear the messages, then wait for the jump to end.
;------------------------------------------------------------------------------
ScrGo:
L1050:  .byte $14, <JUMPS_AGAIN, >JUMPS_AGAIN, <L105B, >L105B ;IFNZ JUMPS_AGAIN GOTO L105B
L1055:  .byte $10, $02, <TxtGo, >TxtGo, $0C, $36 ;BIGTEXT "GO" at col 12, line 144
L105B:  .byte $0A, $01, <SERVE_REQUEST, >SERVE_REQUEST ;SET SERVE_REQUEST = $01  Serve a clown
L105F:  .byte $0A, $C0, <ERASE_MODE, >ERASE_MODE ;SET ERASE_MODE = $C0
L1063:  .byte $0A, $04, <GRAVITY_PERIOD, >GRAVITY_PERIOD ;SET GRAVITY_PERIOD = $04  Gravity every 4 ticks
L1067:  .byte $0A, $00, <SPEED_LEVEL, >SPEED_LEVEL ;SET SPEED_LEVEL = $00
L106B:  .byte $04, $0F              ;DELAY 15 ticks
L106D:  .byte $00                   ;WAIT
L106E:  .byte $02, $11, <TxtBlanks, >TxtBlanks, $08, $32 ;TEXT "                 " at col 8, line 112
L1074:  .byte $10, $04, <TxtBlanks, >TxtBlanks, $04, $36 ;BIGTEXT "    " at col 4, line 144
L107A:  .byte $12, <JUMPS_AGAIN, >JUMPS_AGAIN, <L1091, >L1091 ;IFZ JUMPS_AGAIN GOTO L1091
L107F:  .byte $02, $0B, <TxtBlanks, >TxtBlanks, $8A, $3E ;TEXT "           " at col 10, line 212
L1085:  .byte $10, $06, <TxtBlanks, >TxtBlanks, $04, $36 ;BIGTEXT "      " at col 4, line 144
L108B:  .byte $10, $06, <TxtBlanks, >TxtBlanks, $08, $32 ;BIGTEXT "      " at col 8, line 112
L1091:  .byte $12, <BONUS_GAME, >BONUS_GAME, <L109C, >L109C ;IFZ BONUS_GAME GOTO L109C
L1096:  .byte $02, $0F, <TxtAdditionalGame, >TxtAdditionalGame, $88, $3E ;TEXT "ADDITIONAL GAME" at col 8, line 212
L109C:  .byte $0A, $00, <JUMPS_AGAIN, >JUMPS_AGAIN ;SET JUMPS_AGAIN = $00
L10A0:  .byte $0A, $01, <TUNE_ON, >TUNE_ON ;SET TUNE_ON = $01

ScrJump:
L10A4:  .byte $00                   ;WAIT  The jump is played here; SplatDone starts TMR_SCRIPT to move on
L10A5:  .byte $04, $3C              ;DELAY 60 ticks
L10A7:  .byte $00                   ;WAIT
L10A8:  .byte $08, <ScrTurn, >ScrTurn ;GOTO ScrTurn  Next jump (or AttractScript when GameOver has changed SCRIPT_PTR)

;------------------------------------------------------------------------------
; CoinageScripts - Script entered by COINSTART for each coinage setting (INP_DIP b0-b1).
;------------------------------------------------------------------------------
CoinageScripts:
L10AB:  .word ScrCoin1C1P           ;coinage 0: 1 coin 1 player
L10AD:  .word ScrCoin1C2P           ;coinage 1: 1 coin 2 players
L10AF:  .word ScrCoin2C2P           ;coinage 2: 2 coins 2 players
L10B1:  .word ScrCoin2C1P           ;coinage 3: 2 coins 1 player

;------------------------------------------------------------------------------
; TxtBlanks - Text. 17 blanks, used to erase messages.
;------------------------------------------------------------------------------
TxtBlanks:
L10B3:  .byte $40, $40, $40, $40, $40, $40, $40, $40 ;"        "
L10BB:  .byte $40, $40, $40, $40, $40, $40, $40, $40 ;"        "
L10C3:  .byte $40                   ;" "

TxtPlayerOneUp:
L10C4:  .byte $50, $4C, $41, $51, $45, $52, $40, $4F ;"PLAYER O"
L10CC:  .byte $4E, $45, $40, $55, $50 ;"NE UP"

TxtPlayerTwo:
L10D1:  .byte $50, $4C, $41, $51, $45, $52, $40 ;"PLAYER "

TxtTwo:
L10D8:  .byte $54, $57, $4F         ;"TWO"

TxtPlayerJumpsAgain:
L10DB:  .byte $50, $4C, $41, $51, $45, $52, $40 ;"PLAYER "

TxtJumpsAgain:
L10E2:  .byte $4A, $55, $4D, $50, $53, $40, $41, $47 ;"JUMPS AG"
L10EA:  .byte $41, $49, $4E         ;"AIN"

TxtAdditionalGame:
L10ED:  .byte $41, $44, $44, $49, $54, $49, $4F, $4E ;"ADDITION"
L10F5:  .byte $41, $4C, $40         ;"AL "

TxtGame:
L10F8:  .byte $47, $41, $4D, $45    ;"GAME"

TxtOver:
L10FC:  .byte $4F, $56, $45, $52    ;"OVER"

TxtHighScore:
L1100:  .byte $48, $49, $47, $48, $40, $53, $43, $4F ;"HIGH SCO"
L1108:  .byte $52, $45              ;"RE"

TxtZero:
L110A:  .byte $30                   ;"0"

TxtSame:
L110B:  .byte $53, $41, $4D, $45    ;"SAME"

TxtGo:
L110F:  .byte $47, $4F              ;"GO"

TxtGetReady:
L1111:  .byte $47, $45, $54, $40, $52, $45, $41, $44 ;"GET READ"
L1119:  .byte $51                   ;"Y"

TxtBonus:
L111A:  .byte $42, $4F, $4E, $55, $53 ;"BONUS"

TxtInsertCoin:
L111F:  .byte $4B, $40, $49, $4E, $53, $45, $52, $54 ;"v INSERT"
L1127:  .byte $40, $43, $4F, $49, $4E ;" COIN"

TxtToStartGame:
L112C:  .byte $54, $4F, $40, $53, $54, $41, $52, $54 ;"TO START"
L1134:  .byte $40, $47, $41, $4D, $45 ;" GAME"

TxtPressOnePlayerButton:
L1139:  .byte $50, $52, $45, $53, $53, $40, $4F, $4E ;"PRESS ON"
L1141:  .byte $45, $40              ;"E "

TxtPlayerButton:
L1143:  .byte $50, $4C, $41, $51, $45, $52, $40, $42 ;"PLAYER B"
L114B:  .byte $55, $54, $54, $4F, $4E ;"UTTON"

TxtDeposit2ndCoin:
L1150:  .byte $44, $45, $50, $4F, $53, $49, $54, $40 ;"DEPOSIT "
L1158:  .byte $32, $4E, $44, $40, $43, $4F, $49, $4E ;"2ND COIN"

TxtFor2PlayerGame:
L1160:  .byte $46                   ;"F"

TxtOr:
L1161:  .byte $4F, $52, $40, $32, $40, $50, $4C, $41 ;"OR 2 PLA"
L1169:  .byte $51, $45, $52, $40, $47, $41, $4D, $45 ;"YER GAME"

TxtPressTwo:
L1171:  .byte $50, $52, $45, $53, $53, $40, $54, $57 ;"PRESS TW"
L1179:  .byte $4F                   ;"O"
L117A:  .byte $00                   ;unused

;==============================================================================
; SECTION 6  Timer events ($117B-$1348)
;   The interrupt counts the timers down (TickTimers) and posts expiries as bits;
;   the main loop picks the bits up here and calls one routine per timer.
;==============================================================================

;------------------------------------------------------------------------------
; CheckTimeout - If TMR_TIMEOUT has run out, send the script to TIMEOUT_PTR.
;------------------------------------------------------------------------------
CheckTimeout:
L117B:  LXI  H,EVT_TIMEOUT
L117E:  MOV  A,M                    ;Event bits from the interrupt
L117F:  ANA  A
L1180:  RZ                          ;None
L1181:  MVI  M,$00                  ;Taken
L1183:  RAR                         ;b0: the timeout
L1184:  PUSH PSW
L1185:  CC   ScriptTimeout          ;Jump the script
L1188:  POP  PSW
L1189:  RET

;------------------------------------------------------------------------------
; ScriptTimeout - SCRIPT_PTR = TIMEOUT_PTR, unless TIMEOUT_HOLD.
;------------------------------------------------------------------------------
ScriptTimeout:
L118A:  LDA  TIMEOUT_HOLD           ;A coin was taken: the timeout is off
L118D:  ANA  A
L118E:  RNZ
L118F:  LHLD TIMEOUT_PTR
L1192:  SHLD SCRIPT_PTR
L1195:  RET

;------------------------------------------------------------------------------
; RunTimerEvents - Call the handler of every 30 Hz timer that has expired.
;------------------------------------------------------------------------------
RunTimerEvents:
L1196:  LXI  H,EVT_TIMERS
L1199:  MOV  A,M                    ;Event bits from the interrupt
L119A:  ANA  A
L119B:  RZ                          ;None
L119C:  MVI  M,$00                  ;Taken
L119E:  RAR                         ;b0: TMR_REFILL
L119F:  PUSH PSW
L11A0:  CC   RefillRows
L11A3:  POP  PSW
L11A4:  RAR                         ;b1: TMR_HIT_LOCKOUT has no handler
L11A5:  RAR                         ;b2: TMR_SPLAT
L11A6:  PUSH PSW
L11A7:  CC   SplatStep
L11AA:  POP  PSW
L11AB:  RAR                         ;b3: TMR_GRAVITY
L11AC:  PUSH PSW
L11AD:  CC   GravityTick
L11B0:  POP  PSW
L11B1:  RAR                         ;b4: TMR_SERVE_JUMP
L11B2:  PUSH PSW
L11B3:  CC   ServeJump
L11B6:  POP  PSW
L11B7:  RAR                         ;b5: TMR_WALK
L11B8:  PUSH PSW
L11B9:  CC   WalkStep
L11BC:  POP  PSW
L11BD:  RAR                         ;b6: TMR_SOUND_OFF
L11BE:  PUSH PSW
L11BF:  CC   SoundOff
L11C2:  POP  PSW
L11C3:  RAR                         ;b7: TMR_SCRIPT
L11C4:  PUSH PSW
L11C5:  CC   ScriptTimerDone
L11C8:  POP  PSW
L11C9:  RET

;------------------------------------------------------------------------------
; SplatStep - TMR_SPLAT: next of the three splat pictures, then SplatDone.
;------------------------------------------------------------------------------
SplatStep:
L11CA:  LXI  H,SPLAT_CTR
L11CD:  DCR  M                      ;Pictures left
L11CE:  JZ   SplatDone              ;None: the jump is over
L11D1:  MVI  A,$02                  ;Next picture in 2 ticks
L11D3:  STA  TMR_SPLAT
L11D6:  LHLD FLYER_PTR
L11D9:  INX  H                      ;CL_FRAME
L11DA:  INR  M                      ;$0F -> $10 -> $11: the clown sinks into the floor
L11DB:  RET

;------------------------------------------------------------------------------
; SplatDone - The jump is over: next turn, next player or game over.
;   The flyer is parked below the floor. Attract mode: restart the demo in a
;   second. In a game: an extra jump (JUMPS_AGAIN) costs nothing; with two
;   players the turn passes to player 2 first and a jump is used only after
;   player 2's turn; when the last jump is used the game is over.
;------------------------------------------------------------------------------
SplatDone:
L11DC:  LHLD FLYER_PTR
L11DF:  INX  H                      ;-> CL_XVEL
L11E0:  INX  H
L11E1:  XRA  A
L11E2:  MOV  M,A                    ;Stop
L11E3:  INX  H
L11E4:  INX  H
L11E5:  MOV  M,A                    ;CL_YVEL
L11E6:  INX  H
L11E7:  MVI  M,$DC                  ;CL_Y: under the floor line
L11E9:  LDA  GAME_ACTIVE            ;Game on?
L11EC:  ANA  A
L11ED:  JZ   DemoOver               ;No: attract demo
L11F0:  LDA  JUMPS_AGAIN            ;Extra jump earned?
L11F3:  ANA  A
L11F4:  JNZ  NextTurn               ;Yes: same player, same jumps
L11F7:  LDA  TWO_PLAYERS            ;Two players?
L11FA:  ANA  A
L11FB:  JZ   L1209                  ;No
L11FE:  LDA  PLAYER                 ;Other player
L1201:  XRI  $FF
L1203:  STA  NEXT_PLAYER            ;next
L1206:  JNZ  NextTurn               ;Player 2 is up now: nothing used yet
L1209:  LDA  JUMPS_LEFT             ;Both have jumped (or one player):
L120C:  DCR  A                      ;one jump used
L120D:  JZ   GameOver               ;That was the last
L1210:  STA  NEXT_JUMPS_LEFT        ;Jumps left for the next turn

NextTurn:
L1213:  MVI  A,$01                  ;TMR_SCRIPT = 1: the script leaves ScrJump
L1215:  STA  TMR_SCRIPT
L1218:  RET

;------------------------------------------------------------------------------
; GameOver - Back to the attract script; play the tune; update the high score.
;------------------------------------------------------------------------------
GameOver:
L1219:  LDA  BONUS_GAME             ;Remember whether this game won a bonus game
L121C:  STA  PREV_BONUS_GAME
L121F:  LXI  H,AttractScript        ;Script: attract mode
L1222:  SHLD SCRIPT_PTR
L1225:  LXI  H,GameOverTune         ;Game over tune
L1228:  SHLD TUNE_PTR
L122B:  LXI  D,P1_SCORE             ;Player 1 score
L122E:  LXI  H,HI_SCORE             ;against the high score
L1231:  CALL CheckHighScore
L1234:  INX  D                      ;Player 2 score: falls into CheckHighScore
L1235:  INX  D
L1236:  INX  D

;------------------------------------------------------------------------------
; CheckHighScore - If the 2-byte BCD score at DE beats the one at HL, copy it there.
;------------------------------------------------------------------------------
CheckHighScore:
L1237:  LDAX D                      ;High bytes
L1238:  CMP  M
L1239:  RC                          ;Lower
L123A:  JNZ  CopyScore              ;Higher: new high score
L123D:  INX  D                      ;Equal: low bytes
L123E:  LDAX D
L123F:  DCX  D
L1240:  INX  H
L1241:  CMP  M
L1242:  DCX  H
L1243:  RC                          ;Lower

CopyScore:
L1244:  LDAX D
L1245:  INX  D
L1246:  MOV  M,A
L1247:  INX  H
L1248:  LDAX D
L1249:  DCX  D
L124A:  MOV  M,A
L124B:  DCX  H
L124C:  RET

;------------------------------------------------------------------------------
; DemoOver - Attract mode splat: restart the demo one second from now.
;------------------------------------------------------------------------------
DemoOver:
L124D:  MVI  A,$01
L124F:  STA  TMR_TIMEOUT            ;TMR_TIMEOUT = 1 s (TIMEOUT_PTR is ScrDemo)
L1252:  STA  SCRIPT_HOLD            ;Keep the demo loop's DELAY from moving the script
L1255:  RET

;------------------------------------------------------------------------------
; GravityTick - TMR_GRAVITY: flyer YVEL + 1; restart the timer from GRAVITY_PERIOD.
;   No pull while the clown walks on its ledge or during a freeze.
;------------------------------------------------------------------------------
GravityTick:
L1256:  LDA  SERVING                ;Still on the ledge?
L1259:  ANA  A
L125A:  JNZ  RestartGravity
L125D:  LDA  FREEZE_REQ             ;Frozen?
L1260:  ANA  A
L1261:  JNZ  RestartGravity
L1264:  LHLD FLYER_PTR
L1267:  MOV  A,M                    ;Splatted: leave it (the timer is not restarted)
L1268:  ANI  $08
L126A:  RNZ
L126B:  LXI  D,CL_YVEL
L126E:  DAD  D
L126F:  INR  M                      ;One more pixel per update downward

RestartGravity:
L1270:  LDA  GRAVITY_PERIOD
L1273:  STA  TMR_GRAVITY
L1276:  RET

;------------------------------------------------------------------------------
; ServeJump - TMR_SERVE_JUMP: the served clown jumps off its ledge.
;------------------------------------------------------------------------------
ServeJump:
L1277:  LHLD FLYER_PTR
L127A:  MOV  A,M
L127B:  ANI  $EF                    ;No longer slow
L127D:  MOV  M,A
L127E:  INX  H
L127F:  MVI  A,$01                  ;Picture 1: tumbling
L1281:  MOV  M,A
L1282:  STA  TMR_GRAVITY            ;Gravity starts on the next tick
L1285:  INX  H
L1286:  INX  H
L1287:  INX  H
L1288:  MVI  M,$FE                  ;YVEL: 2 up
L128A:  XRA  A
L128B:  STA  SERVING                ;Serve is over
L128E:  RET

;------------------------------------------------------------------------------
; WalkStep - TMR_WALK: every 3 ticks, step the walking clown's picture +1 +1 -1 -1.
;------------------------------------------------------------------------------
WalkStep:
L128F:  LDA  SERVING                ;Still walking?
L1292:  ANA  A
L1293:  RZ
L1294:  MVI  A,$03                  ;Again in 3 ticks
L1296:  STA  TMR_WALK
L1299:  LHLD FLYER_PTR
L129C:  LXI  D,WALK_PHASE
L129F:  LDAX D
L12A0:  INR  A
L12A1:  CPI  $04                    ;Phase 0-3
L12A3:  JC   L12A7
L12A6:  XRA  A
L12A7:  STAX D
L12A8:  MVI  A,$01                  ;Phases 1, 2: next picture
L12AA:  JPO  L12AF                  ;(parity of the compare above)
L12AD:  MVI  A,$FF                  ;Phases 3, 0: previous picture
L12AF:  INX  H                      ;CL_FRAME
L12B0:  ADD  M
L12B1:  MOV  M,A
L12B2:  RET

;------------------------------------------------------------------------------
; ScriptTimerDone - TMR_SCRIPT: step the script past the WAIT it is on, unless SCRIPT_HOLD.
;------------------------------------------------------------------------------
ScriptTimerDone:
L12B3:  LDA  SCRIPT_HOLD
L12B6:  ANA  A
L12B7:  RNZ
L12B8:  LHLD SCRIPT_PTR
L12BB:  INX  H
L12BC:  SHLD SCRIPT_PTR
L12BF:  RET

;------------------------------------------------------------------------------
; SoundOff - TMR_SOUND_OFF: end the pop / hit / miss sound, leave the board enabled.
;------------------------------------------------------------------------------
SoundOff:
L12C0:  MVI  A,$08
L12C2:  OUT  OUT_SOUND
L12C4:  RET

;------------------------------------------------------------------------------
; RunTimerEvents2 - Call the handlers of the second timer group.
;------------------------------------------------------------------------------
RunTimerEvents2:
L12C5:  LXI  H,EVT_TIMERS2
L12C8:  MOV  A,M                    ;Event bits from the interrupt
L12C9:  ANA  A
L12CA:  RZ
L12CB:  MVI  M,$00
L12CD:  RAR                         ;b0: TMR_FREEZE
L12CE:  PUSH PSW
L12CF:  CC   EndFreeze
L12D2:  POP  PSW
L12D3:  RAR                         ;b1: TMR_TUMBLE has no handler
L12D4:  RAR                         ;b2: TMR_COIN_CTR
L12D5:  PUSH PSW
L12D6:  CC   CoinCounterOff
L12D9:  POP  PSW
L12DA:  RET

;------------------------------------------------------------------------------
; RefillRows - TMR_REFILL: put back the balloons of the cleared row(s).
;------------------------------------------------------------------------------
RefillRows:
L12DB:  LHLD REFILL_ROW_PTR         ;The row, or the player's first row
L12DE:  IN   INP_DIP                ;Balloon resets switch
L12E0:  ANI  $10
L12E2:  JZ   L1303                  ;Each row
L12E5:  XRA  A                      ;All rows: nothing pending any more
L12E6:  STA  REFILL_PENDING
L12E9:  LXI  D,P2_OFFSET
L12EC:  MVI  B,$24                  ;Top row
L12EE:  CALL FillBalloonRow
L12F1:  LXI  D,P2_OFFSET
L12F4:  DAD  D                      ;Skip the other player's row
L12F5:  MVI  B,$38                  ;Middle row
L12F7:  CALL FillBalloonRow
L12FA:  LXI  D,P2_OFFSET
L12FD:  DAD  D
L12FE:  MVI  B,$4E                  ;Bottom row
L1300:  JMP  FillBalloonRow
L1303:  LXI  D,REFILL_PENDING       ;Each row: REFILL_PENDING holds the row's Y
L1306:  LDAX D
L1307:  MOV  B,A
L1308:  XRA  A
L1309:  STAX D                      ;Nothing pending any more
L130A:  JMP  FillBalloonRow

;------------------------------------------------------------------------------
; EndFreeze - TMR_FREEZE: let flyer and balloons move again and erase the BONUS message.
;   A flyer that is up in the balloon rows (Y below $60) is stopped dead so that
;   it drops straight down.
;------------------------------------------------------------------------------
EndFreeze:
L130D:  LDA  GAME_ACTIVE
L1310:  ANA  A
L1311:  RZ                          ;Attract mode: nothing was frozen
L1312:  XRA  A
L1313:  STA  FREEZE_REQ
L1316:  STA  FREEZE
L1319:  LHLD FLYER_PTR
L131C:  LXI  D,CL_Y
L131F:  DAD  D
L1320:  MOV  A,M                    ;Flyer Y
L1321:  CPI  $60                    ;Among the balloons?
L1323:  JNC  L132B                  ;No
L1326:  DCX  H
L1327:  MOV  M,D                    ;YVEL = 0
L1328:  DCX  H
L1329:  DCX  H
L132A:  MOV  M,D                    ;XVEL = 0
L132B:  LXI  H,TxtBlanks            ;Blanks
L132E:  PUSH H
L132F:  LXI  D,$3486                ;over the big BONUS
L1332:  MVI  A,$05
L1334:  CALL DrawBigString
L1337:  POP  H
L1338:  LXI  D,$388D                ;and over the value
L133B:  MVI  A,$05
L133D:  JMP  DrawString

;------------------------------------------------------------------------------
; CoinCounterOff - TMR_COIN_CTR: end the coin counter pulse.
;------------------------------------------------------------------------------
CoinCounterOff:
L1340:  LXI  H,OUT3_SHADOW
L1343:  MOV  A,M
L1344:  ANI  $FE
L1346:  MOV  M,A
L1347:  RET
L1348:  .byte $00                   ;unused

;==============================================================================
; SECTION 7  Switch test and RAM clear ($1349-$1412)
;==============================================================================

;------------------------------------------------------------------------------
; SwitchTest - Switch test, entered from the RAM test when the coin switch is held.
;   Shows COIN ON / OFF (and drives the coin counter while the switch is
;   down), PLAYER 1 ON / OFF and PLAYER 2 ON / OFF for the start buttons, with
;   the floor, the ledges and the seesaw following the paddle. Pressing a start
;   button selects that player's paddle. Never leaves: only a reset ends it.
;------------------------------------------------------------------------------
SwitchTest:
L1349:  XRA  A                      ;A = 0: clear all RAM
L134A:  CALL ClearRamTop
L134D:  EI                          ;The interrupts draw the seesaw
L134E:  OUT  OUT_WATCHDOG
L1350:  CALL DrawPlayfield
L1353:  MVI  A,$80                  ;Seesaw on screen
L1355:  STA  SEESAW_STATE
L1358:  LXI  H,TxtCoin              ;"COIN"
L135B:  LXI  D,$3000                ;Line 96
L135E:  MVI  A,$04                  ;PADDLE_ENABLE: any non-zero value
L1360:  STA  PADDLE_ENABLE
L1363:  CALL DrawString             ;4 characters; HL moves on to "OFF"
L1366:  INX  D                      ;One column of space
L1367:  IN   INP_SWITCH             ;Coin switch, active low
L1369:  ANI  $40
L136B:  JNZ  L1373                  ;Up: "OFF", coin counter off ($40 has b0 clear)
L136E:  LXI  H,TxtOn                ;Down: "ON "
L1371:  MVI  A,$01                  ;and coin counter on
L1373:  STA  OUT3_SHADOW
L1376:  MVI  A,$03                  ;3 characters
L1378:  CALL DrawString
L137B:  LXI  D,$3400                ;Line 128
L137E:  CALL DrawPlayerWord         ;"PLAYER", A = 1
L1381:  CALL DrawCharReadSwitches   ;"1"; A = the switches
L1384:  ANI  $20                    ;1-player start down?
L1386:  JNZ  L138E
L1389:  MVI  A,$00                  ;Yes: seesaw follows paddle 1 (flags are kept for DrawOnOff)
L138B:  STA  PLAYER
L138E:  CALL DrawOnOff
L1391:  LXI  D,$3800                ;Line 160
L1394:  CALL DrawPlayerWord         ;"PLAYER"
L1397:  CALL DrawNextChar           ;"2"
L139A:  ANI  $10                    ;2-player start down?
L139C:  JNZ  L13A4
L139F:  MVI  A,$FF                  ;Yes: seesaw follows paddle 2
L13A1:  STA  PLAYER
L13A4:  CALL DrawOnOff
L13A7:  LXI  H,$0400                ;Short delay
L13AA:  DCX  H
L13AB:  MOV  A,H
L13AC:  ORA  L
L13AD:  JNZ  L13AA
L13B0:  JMP  L134D

;------------------------------------------------------------------------------
; DrawPlayerWord - Draw "PLAYER" at DE and leave a blank column; returns A = 1.
;------------------------------------------------------------------------------
DrawPlayerWord:
L13B3:  LXI  H,TxtPlayer
L13B6:  MVI  A,$06
L13B8:  CALL DrawString
L13BB:  INX  D
L13BC:  INR  A
L13BD:  RET

;------------------------------------------------------------------------------
; DrawNextChar - Skip one character of text, then as DrawCharReadSwitches.
;------------------------------------------------------------------------------
DrawNextChar:
L13BE:  INX  H

;------------------------------------------------------------------------------
; DrawCharReadSwitches - Draw A characters from HL at DE; return A = INP_SWITCH.
;------------------------------------------------------------------------------
DrawCharReadSwitches:
L13BF:  CALL DrawString
L13C2:  IN   INP_SWITCH
L13C4:  RET

;------------------------------------------------------------------------------
; DrawOnOff - One blank column, then "ON " if Z is set, else "OFF".
;------------------------------------------------------------------------------
DrawOnOff:
L13C5:  INX  D
L13C6:  LXI  H,TxtOn
L13C9:  JZ   L13CF
L13CC:  LXI  H,TxtOff
L13CF:  MVI  A,$03
L13D1:  JMP  DrawString

TxtCoin:
L13D4:  .byte $43, $4F, $49, $4E    ;"COIN"

TxtOff:
L13D8:  .byte $4F, $46, $46         ;"OFF"

TxtOn:
L13DB:  .byte $4F, $4E, $40         ;"ON "

TxtPlayer:
L13DE:  .byte $50, $4C, $41, $51, $45, $52, $31, $32 ;"PLAYER12"
L13E6:  .byte $00                   ;unused

;------------------------------------------------------------------------------
; ClearRamTop - Zero A x 32 bytes downward from $4000 (A = 0: all of RAM).
;   Done by pushing zeros, so it cannot return through the stack: the return
;   address is taken off first and jumped to at the end. Leaves the stack at
;   $2400 and interrupts off, and copies NEXT_PLAYER to PLAYER and
;   NEXT_JUMPS_LEFT to JUMPS_LEFT. The script uses $FE (everything from $2040:
;   balloon rows, objects, screen) and $F4 (from $2180: objects, state, screen).
;------------------------------------------------------------------------------
ClearRamTop:
L13E7:  DI
L13E8:  POP  H                      ;HL = return address
L13E9:  LXI  B,$0000
L13EC:  LXI  SP,$4000               ;Just past the end of RAM
L13EF:  PUSH B                      ;16 pushes = 32 bytes
L13F0:  PUSH B
L13F1:  PUSH B
L13F2:  PUSH B
L13F3:  PUSH B
L13F4:  PUSH B
L13F5:  PUSH B
L13F6:  PUSH B
L13F7:  PUSH B
L13F8:  PUSH B
L13F9:  PUSH B
L13FA:  PUSH B
L13FB:  PUSH B
L13FC:  PUSH B
L13FD:  PUSH B
L13FE:  PUSH B
L13FF:  DCR  A
L1400:  JNZ  L13EF                  ;Next 32 bytes
L1403:  LXI  SP,$2400               ;Stack back at the top of work RAM
L1406:  LDA  NEXT_PLAYER            ;Player for this turn
L1409:  STA  PLAYER
L140C:  LDA  NEXT_JUMPS_LEFT        ;Jumps left for this turn
L140F:  STA  JUMPS_LEFT
L1412:  PCHL                        ;Return

;==============================================================================
; SECTION 8  Script commands ($1413-$1525)
;   Handlers reached from MainLoop with DE -> the command's arguments. Each
;   stores the new SCRIPT_PTR and returns to MainLoop.
;==============================================================================

;------------------------------------------------------------------------------
; ScriptOps - Handler for each script opcode ($02, $04 ... $20).
;------------------------------------------------------------------------------
ScriptOps:
L1413:  .word OpText                ;$02 TEXT
L1415:  .word OpDelay               ;$04 DELAY
L1417:  .word OpTimeout             ;$06 TIMEOUT
L1419:  .word OpGoto                ;$08 GOTO
L141B:  .word OpSet                 ;$0A SET
L141D:  .word OpClear               ;$0C CLEAR
L141F:  .word OpScore               ;$0E SCORE
L1421:  .word OpBigText             ;$10 BIGTEXT
L1423:  .word OpIfZ                 ;$12 IFZ
L1425:  .word OpIfNZ                ;$14 IFNZ
L1427:  .word OpCoinStart           ;$16 COINSTART
L1429:  .word OpRow                 ;$18 ROW
L142B:  .word OpDecCoin             ;$1A DECCOIN
L142D:  .word OpIncCoin             ;$1C INCCOIN
L142F:  .word OpTone                ;$1E TONE
L1431:  .word OpQuiet               ;$20 QUIET

;------------------------------------------------------------------------------
; OpClear - CLEAR n: ClearRamTop with A = n.
;------------------------------------------------------------------------------
OpClear:
L1433:  XCHG                        ;HL -> argument
L1434:  MOV  A,M
L1435:  INX  H
L1436:  SHLD SCRIPT_PTR             ;Script continues after it
L1439:  JMP  ClearRamTop            ;Returns to MainLoop (the address MainLoop pushed)

;------------------------------------------------------------------------------
; OpBigText - BIGTEXT n, text, screen: DrawBigString.
;------------------------------------------------------------------------------
OpBigText:
L143C:  LXI  H,DrawBigString
L143F:  JMP  OpTextCommon

;------------------------------------------------------------------------------
; OpText - TEXT n, text, screen: DrawString.
;------------------------------------------------------------------------------
OpText:
L1442:  LXI  H,DrawString

OpTextCommon:
L1445:  PUSH H                      ;The draw routine is entered by the RET below
L1446:  XCHG
L1447:  MOV  A,M                    ;A = character count
L1448:  INX  H
L1449:  MOV  E,M                    ;Text address,
L144A:  INX  H
L144B:  MOV  D,M
L144C:  INX  H
L144D:  PUSH D                      ;kept on the stack
L144E:  CALL ScriptWord             ;DE = screen address; script pointer stored
L1451:  POP  H                      ;HL = text address
L1452:  RET                         ;To the draw routine, which returns to MainLoop

;------------------------------------------------------------------------------
; OpDelay - DELAY n: start TMR_SCRIPT; ScriptTimerDone may step the script.
;------------------------------------------------------------------------------
OpDelay:
L1453:  XRA  A                      ;Clear SCRIPT_HOLD
L1454:  STA  SCRIPT_HOLD
L1457:  XCHG
L1458:  MOV  A,M
L1459:  STA  TMR_SCRIPT             ;Ticks
L145C:  INX  H
L145D:  SHLD SCRIPT_PTR
L1460:  RET

;------------------------------------------------------------------------------
; OpTimeout - TIMEOUT n, addr: start TMR_TIMEOUT and set where it sends the script.
;------------------------------------------------------------------------------
OpTimeout:
L1461:  XRA  A                      ;Clear TIMEOUT_HOLD
L1462:  STA  TIMEOUT_HOLD
L1465:  XCHG
L1466:  MOV  A,M
L1467:  STA  TMR_TIMEOUT            ;Seconds
L146A:  INX  H
L146B:  CALL ScriptWord             ;DE = address
L146E:  XCHG
L146F:  SHLD TIMEOUT_PTR
L1472:  RET

;------------------------------------------------------------------------------
; OpGoto - GOTO addr.
;------------------------------------------------------------------------------
OpGoto:
L1473:  XCHG
L1474:  MOV  E,M
L1475:  INX  H
L1476:  MOV  D,M
L1477:  XCHG
L1478:  SHLD SCRIPT_PTR
L147B:  RET

;------------------------------------------------------------------------------
; OpSet - SET value, addr: store a byte.
;------------------------------------------------------------------------------
OpSet:
L147C:  CALL ScriptByteWord         ;A = value, DE = address
L147F:  STAX D
L1480:  RET

;------------------------------------------------------------------------------
; OpScore - SCORE score, screen: draw a BCD score as 5 characters.
;------------------------------------------------------------------------------
OpScore:
L1481:  XCHG
L1482:  MOV  C,M                    ;BC = address of the score
L1483:  INX  H
L1484:  MOV  B,M
L1485:  INX  H
L1486:  PUSH H
L1487:  LXI  H,TEXT_BUF             ;Format into TEXT_BUF
L148A:  CALL FormatScore
L148D:  POP  H
L148E:  CALL ScriptWord             ;DE = screen address; script pointer stored
L1491:  LXI  H,TEXT_BUF
L1494:  MVI  A,$05                  ;5 characters
L1496:  JMP  DrawString

;------------------------------------------------------------------------------
; OpIfZ - IFZ addr, target: jump if the byte at addr is 0.
;------------------------------------------------------------------------------
OpIfZ:
L1499:  CALL OpTestArgs
L149C:  JNZ  L14A0                  ;Not zero: continue after the arguments
L149F:  XCHG                        ;Zero: take the target
L14A0:  SHLD SCRIPT_PTR
L14A3:  RET

;------------------------------------------------------------------------------
; OpIfNZ - IFNZ addr, target: jump if the byte at addr is not 0.
;------------------------------------------------------------------------------
OpIfNZ:
L14A4:  CALL OpTestArgs
L14A7:  JZ   L14AB                  ;Zero: continue after the arguments
L14AA:  XCHG                        ;Not zero: take the target
L14AB:  SHLD SCRIPT_PTR
L14AE:  RET

;------------------------------------------------------------------------------
; OpTestArgs - A = byte at the first argument (flags set), DE = second argument, HL -> next command.
;------------------------------------------------------------------------------
OpTestArgs:
L14AF:  XCHG
L14B0:  MOV  E,M
L14B1:  INX  H
L14B2:  MOV  D,M
L14B3:  INX  H
L14B4:  LDAX D
L14B5:  MOV  E,M
L14B6:  INX  H
L14B7:  MOV  D,M
L14B8:  INX  H
L14B9:  ANA  A
L14BA:  RET

;------------------------------------------------------------------------------
; OpCoinStart - COINSTART: if a coin is in, take it and jump to the script for the coinage setting.
;   Also sets the jumps for the game (3 or 4, INP_DIP b6) and holds off both
;   script timers so that neither the demo's DELAY nor its TIMEOUT disturbs the
;   coin scripts.
;------------------------------------------------------------------------------
OpCoinStart:
L14BB:  LXI  H,COINS
L14BE:  MOV  A,M
L14BF:  ANA  A
L14C0:  RZ                          ;No coin: the script goes on
L14C1:  DCR  M                      ;Take the coin
L14C2:  STA  SCRIPT_HOLD            ;A is non-zero: SCRIPT_HOLD
L14C5:  STA  TIMEOUT_HOLD           ;and TIMEOUT_HOLD
L14C8:  IN   INP_DIP
L14CA:  MOV  D,A
L14CB:  RAL                         ;b6 to carry
L14CC:  RAL
L14CD:  MVI  A,$03                  ;3 jumps
L14CF:  JNC  L14D3
L14D2:  INR  A                      ;or 4
L14D3:  STA  NEXT_JUMPS_LEFT
L14D6:  MOV  A,D                    ;Coinage, b0-b1
L14D7:  ANI  $03
L14D9:  MOV  C,A
L14DA:  MVI  B,$00
L14DC:  LXI  H,CoinageScripts       ;Script for this coinage
L14DF:  DAD  B
L14E0:  DAD  B
L14E1:  MOV  E,M
L14E2:  INX  H
L14E3:  MOV  D,M
L14E4:  XCHG
L14E5:  SHLD SCRIPT_PTR
L14E8:  RET

;------------------------------------------------------------------------------
; OpRow - ROW y, addr: fill a balloon row.
;------------------------------------------------------------------------------
OpRow:
L14E9:  CALL ScriptByteWord         ;A = y, DE = row
L14EC:  MOV  B,A
L14ED:  XCHG

;------------------------------------------------------------------------------
; FillBalloonRow - Fill the row at HL with 12 balloons at height B, 21 pixels apart from X = 0.
;   Returns HL after the row.
;------------------------------------------------------------------------------
FillBalloonRow:
L14EE:  LXI  D,$0C00                ;D = 12 balloons, E = X
L14F1:  MVI  M,$80                  ;Present
L14F3:  INX  H
L14F4:  MOV  M,E                    ;X
L14F5:  MOV  A,E
L14F6:  ADI  $15                    ;21 pixels to the next one
L14F8:  MOV  E,A
L14F9:  INX  H
L14FA:  MOV  M,B                    ;Y
L14FB:  INX  H
L14FC:  DCR  D
L14FD:  JNZ  L14F1
L1500:  RET

;------------------------------------------------------------------------------
; ScriptByteWord - A = byte at DE, DE = word after it; SCRIPT_PTR -> after both.
;------------------------------------------------------------------------------
ScriptByteWord:
L1501:  XCHG
L1502:  MOV  A,M
L1503:  INX  H

;------------------------------------------------------------------------------
; ScriptWord - DE = word at HL; SCRIPT_PTR -> after it.
;------------------------------------------------------------------------------
ScriptWord:
L1504:  MOV  E,M
L1505:  INX  H
L1506:  MOV  D,M
L1507:  INX  H
L1508:  SHLD SCRIPT_PTR
L150B:  RET

;------------------------------------------------------------------------------
; OpDecCoin - DECCOIN: COINS - 1.
;------------------------------------------------------------------------------
OpDecCoin:
L150C:  LXI  H,COINS
L150F:  DCR  M
L1510:  RET

;------------------------------------------------------------------------------
; OpIncCoin - INCCOIN: COINS + 1.
;------------------------------------------------------------------------------
OpIncCoin:
L1511:  LXI  H,COINS
L1514:  INR  M
L1515:  RET

;------------------------------------------------------------------------------
; OpTone - TONE: steady tone (note $04).
;------------------------------------------------------------------------------
OpTone:
L1516:  MVI  A,$3F
L1518:  OUT  OUT_TONE_LO
L151A:  MVI  A,$1A
L151C:  OUT  OUT_TONE_HI
L151E:  RET

;------------------------------------------------------------------------------
; OpQuiet - QUIET: tone off, sound board off.
;------------------------------------------------------------------------------
OpQuiet:
L151F:  XRA  A
L1520:  OUT  OUT_TONE_LO
L1522:  OUT  OUT_SOUND
L1524:  RET
L1525:  .byte $00                   ;unused

;==============================================================================
; SECTION 9  Contact handling and scoring ($1526-$17FF)
;   CheckContact (interrupt) reports that the flyer's picture was drawn over
;   something. Here the main loop works out what: floor, seesaw, ledge or
;   balloon, from where the flyer is.
;==============================================================================

;------------------------------------------------------------------------------
; HandleContact - Act on CONTACT_ROW: splat, launch from the seesaw, ledge bounce or balloon pop.
;   Contact height = flyer Y + CONTACT_ROW. $D4 and below: the floor (Splat).
;   $B0-$D3: the seesaw zone (LandOnSeesaw). Above: ContactAbove.
;------------------------------------------------------------------------------
HandleContact:
L1526:  LDA  CONTACT_ROW
L1529:  ANA  A                      ;Nothing touched
L152A:  RZ
L152B:  MOV  B,A                    ;B = row + 1
L152C:  LHLD FLYER_PTR
L152F:  MOV  A,M
L1530:  ANI  $08
L1532:  RNZ                         ;Already splatted
L1533:  INX  H
L1534:  INX  H
L1535:  INX  H                      ;-> CL_X
L1536:  MOV  E,M                    ;E = flyer X
L1537:  INX  H
L1538:  INX  H                      ;-> CL_Y
L1539:  MOV  A,B
L153A:  ADD  M                      ;Height of the contact
L153B:  CPI  $D4                    ;On the floor?
L153D:  JC   ContactNotFloor        ;No

;------------------------------------------------------------------------------
; Splat - The flyer hits the floor (or the wrong part of the seesaw).
;   Puts it on the floor line with the first splat picture, shows one of four
;   words above it and makes the miss sound. SplatStep finishes the animation.
;   With YVEL 1 the clown sinks a line per update until SplatDone; once it is
;   below line 223 the rows of its picture are written at $4000 and up, which
;   is empty ROM space on this board, so they are lost.
;------------------------------------------------------------------------------
Splat:
L1540:  LHLD FLYER_PTR
L1543:  LXI  B,CL_Y
L1546:  DAD  B
L1547:  MVI  M,$D4                  ;On the floor
L1549:  DCX  H
L154A:  MVI  M,$01                  ;YVEL 1: sinks a pixel per update
L154C:  DCX  H
L154D:  DCX  H
L154E:  MOV  M,B                    ;XVEL 0
L154F:  DCX  H
L1550:  MVI  M,$0F                  ;First splat picture
L1552:  DCX  H
L1553:  MOV  A,M
L1554:  ORI  $08                    ;Splatted: no contact, no gravity
L1556:  MOV  M,A
L1557:  MVI  A,$40                  ;Erase by restoring the background
L1559:  STA  ERASE_MODE
L155C:  MVI  A,$03                  ;Three pictures,
L155E:  STA  TMR_SPLAT              ;the first for 3 ticks
L1561:  STA  SPLAT_CTR
L1564:  CALL Random
L1567:  ANI  $03                    ;One of four words
L1569:  MOV  C,A
L156A:  MVI  B,$00
L156C:  LXI  H,SplatWords
L156F:  DAD  B
L1570:  DAD  B
L1571:  DAD  B                      ;3 characters each
L1572:  MOV  A,E                    ;Flyer X
L1573:  CPI  $08
L1575:  JC   L157A                  ;Centre the word:
L1578:  SUI  $08                    ;one character to the left,
L157A:  CPI  $F0
L157C:  JC   L1581
L157F:  MVI  A,$E8                  ;and not off the right side
L1581:  RAR                         ;/ 8: byte column
L1582:  RAR
L1583:  RAR
L1584:  ANI  $1F
L1586:  MOV  E,A
L1587:  MVI  D,$38                  ;DE = $3800 + column: line 160
L1589:  MVI  A,$03
L158B:  CALL DrawString
L158E:  STA  CONTACT_ROW            ;A = 0: contact handled
L1591:  LDA  GAME_ACTIVE            ;Game on?
L1594:  ANA  A
L1595:  RZ
L1596:  MVI  A,$28                  ;Miss sound
L1598:  OUT  OUT_SOUND
L159A:  MVI  A,$07                  ;for 7 ticks
L159C:  STA  TMR_SOUND_OFF
L159F:  RET

;------------------------------------------------------------------------------
; SplatWords - Words shown at a splat, 3 characters each.
;------------------------------------------------------------------------------
SplatWords:
L15A0:  .byte $42, $41, $4D         ;"BAM"
L15A3:  .byte $4F, $4F, $46         ;"OOF"
L15A6:  .byte $55, $47, $48         ;"UGH"
L15A9:  .byte $50, $4F, $57         ;"POW"

ContactNotFloor:
L15AC:  CPI  $B0                    ;In the seesaw zone?
L15AE:  JC   ContactAbove           ;No: higher up

;------------------------------------------------------------------------------
; LandOnSeesaw - Contact in the seesaw zone: launch the rider if the flyer came down on the raised end.
;   The landing zone is 28 pixels wide: flyer X from SEESAW_DRAWN_X - 12 when
;   the right end is down (the left end is up), 20 further right otherwise.
;   Outside it the flyer splats. Inside, the position in the zone (0-6) sets the
;   launch: the middle goes straight up, either side sends the rider that way
;   with an X speed that grows with the distance and with SPEED_LEVEL. The
;   rider becomes the flyer with YVEL = -(SPEED_LEVEL + 5); the old flyer
;   becomes the rider on the end it landed on; the seesaw starts tipping.
;   Every launch scores 10 points.
;------------------------------------------------------------------------------
LandOnSeesaw:
L15B1:  LXI  H,SEESAW_STATE
L15B4:  MOV  A,M
L15B5:  ANI  $20                    ;Which end is down?
L15B7:  MVI  D,$00                  ;Right end down: zone at the left end
L15B9:  JNZ  L15BE
L15BC:  MVI  D,$14                  ;Left end down: zone 20 pixels further right
L15BE:  INX  H                      ;-> SEESAW_DRAWN_X
L15BF:  MOV  A,E                    ;Flyer X
L15C0:  ADI  $0C
L15C2:  SUB  D                      ;- zone start
L15C3:  SUB  M
L15C4:  CPI  $1C                    ;Inside the 28 pixels?
L15C6:  JNC  Splat                  ;No: splat
L15C9:  RAR                         ;Position / 4:
L15CA:  RAR
L15CB:  ANI  $07                    ;0-6
L15CD:  MOV  C,A
L15CE:  DCX  H
L15CF:  MOV  A,M                    ;Seesaw:
L15D0:  ORI  $40                    ;start tipping
L15D2:  MOV  M,A
L15D3:  MVI  B,$00
L15D5:  LHLD RIDER_PTR              ;The rider
L15D8:  PUSH H
L15D9:  LHLD FLYER_PTR
L15DC:  MVI  M,$A0                  ;Old flyer: in use, blank its last picture
L15DE:  SHLD RIDER_PTR              ;It is the rider now
L15E1:  INX  H
L15E2:  INX  H
L15E3:  MOV  M,B                    ;XVEL 0
L15E4:  INX  H
L15E5:  INX  H
L15E6:  MOV  M,B                    ;YVEL 0
L15E7:  INX  H
L15E8:  MVI  M,$C4                  ;Standing on the seesaw
L15EA:  MOV  A,C
L15EB:  SUI  $03                    ;Middle of the zone?
L15ED:  JNZ  L15FA                  ;No
L15F0:  MOV  E,A                    ;Straight up: XVEL 0
L15F1:  LDA  SPEED_LEVEL
L15F4:  ADI  $05                    ;D = launch speed
L15F6:  MOV  D,A
L15F7:  JMP  L160C
L15FA:  JNC  L1608                  ;Right of the middle
L15FD:  CMA                         ;Left: distance 1-3
L15FE:  INR  A
L15FF:  CALL LaunchXSpeed           ;X speed for it
L1602:  CMA                         ;to the left
L1603:  INR  A
L1604:  MOV  E,A
L1605:  JMP  L160C
L1608:  CALL LaunchXSpeed           ;X speed, to the right
L160B:  MOV  E,A
L160C:  MOV  A,D                    ;YVEL = -speed
L160D:  CMA
L160E:  INR  A
L160F:  POP  H                      ;The old rider
L1610:  MVI  C,$04                  ;-> CL_YVEL
L1612:  DAD  B
L1613:  MOV  M,A
L1614:  DCX  H                      ;CL_X:
L1615:  MOV  A,M
L1616:  CPI  $F2                    ;keep it on the screen
L1618:  JC   L161D
L161B:  MVI  M,$F1
L161D:  DCX  H
L161E:  MOV  M,E                    ;CL_XVEL
L161F:  DCX  H
L1620:  DCX  H
L1621:  MVI  M,$A0                  ;In use, blank its rider picture
L1623:  SHLD FLYER_PTR              ;It is the flyer now
L1626:  LXI  H,REBOUND_STEP_CTR     ;Every 4th launch:
L1629:  INR  M
L162A:  MOV  A,M
L162B:  CPI  $04
L162D:  JC   L163D
L1630:  MOV  M,B
L1631:  LXI  H,REBOUND_SPEED        ;popping a balloon on the way up sends the flyer down faster
L1634:  INR  M
L1635:  MOV  A,M
L1636:  CPI  $05
L1638:  JC   L163D
L163B:  MVI  M,$04                  ;up to 4
L163D:  LXI  H,GRAVITY_STEP_CTR     ;Every 2nd launch:
L1640:  INR  M
L1641:  MOV  A,M
L1642:  CPI  $02
L1644:  JC   L1654
L1647:  MOV  M,B
L1648:  LXI  H,GRAVITY_PERIOD       ;gravity pulls less often
L164B:  INR  M
L164C:  MOV  A,M
L164D:  CPI  $09
L164F:  JC   L1654
L1652:  MVI  M,$08                  ;at most every 8 ticks
L1654:  LXI  H,SPEED_STEP_CTR       ;Every 3rd launch:
L1657:  INR  M
L1658:  MOV  A,M
L1659:  CPI  $03
L165B:  JC   L166C
L165E:  MOV  M,B
L165F:  LXI  H,SPEED_LEVEL          ;launches get faster
L1662:  MOV  A,M
L1663:  INR  A
L1664:  CPI  $05
L1666:  JC   L166B
L1669:  MVI  A,$04                  ;up to level 4
L166B:  MOV  M,A
L166C:  MVI  A,$03                  ;No contact for 3 ticks
L166E:  STA  TMR_HIT_LOCKOUT
L1671:  CALL ClearContact           ;Contact handled
L1674:  LDA  GAME_ACTIVE            ;Game on?
L1677:  ANA  A
L1678:  RZ
L1679:  MVI  A,$18                  ;Springboard sound
L167B:  OUT  OUT_SOUND
L167D:  MVI  A,$07                  ;for 7 ticks
L167F:  STA  TMR_SOUND_OFF
L1682:  LXI  B,$0001                ;10 points: falls into AddScore

;------------------------------------------------------------------------------
; AddScore - Add BC (BCD, tens of points: B high, C low) to the current player's score; award bonuses.
;   Bonus game (INP_DIP b2-b3: at 9000, 11000 or 13000): once per game, and not
;   in a game that follows a bonus game; adds COINS_PER_GAME to COINS and
;   shows ADDITIONAL GAME. Extra jump (INP_DIP b5: at 3000 or 4000): once per
;   player; sets JUMPS_AGAIN, plays the bonus tune, freezes for 3 seconds and
;   shows BONUS / PLAYER JUMPS AGAIN.
;------------------------------------------------------------------------------
AddScore:
L1685:  LDA  GAME_ACTIVE
L1688:  ANA  A
L1689:  RZ                          ;Attract mode: no score
L168A:  LDA  PLAYER                 ;Which player?
L168D:  ANA  A
L168E:  LXI  H,P1_EXTRA_JUMP        ;HL -> that player's extra-jump flag
L1691:  LXI  D,P1_SCORE+1           ;DE -> low byte of the score
L1694:  JZ   L169B                  ;Player 1
L1697:  INX  H
L1698:  LXI  D,P2_SCORE+1
L169B:  LDAX D
L169C:  ADD  C                      ;Low byte
L169D:  DAA
L169E:  STAX D
L169F:  DCX  D
L16A0:  LDAX D
L16A1:  ADC  B                      ;High byte
L16A2:  DAA
L16A3:  STAX D
L16A4:  MOV  B,A                    ;B = thousands and hundreds
L16A5:  LDA  PREV_BONUS_GAME        ;Was the last game a bonus game?
L16A8:  ANA  A
L16A9:  JNZ  CheckExtraJump         ;Yes: no bonus game in this one
L16AC:  LXI  D,BONUS_GAME           ;Already awarded?
L16AF:  LDAX D
L16B0:  ANA  A
L16B1:  JNZ  CheckExtraJump
L16B4:  IN   INP_DIP                ;Bonus game setting
L16B6:  ANI  $0C
L16B8:  JZ   CheckExtraJump         ;Off
L16BB:  RAR                         ;2, 4, 6
L16BC:  ADI  $06                    ;8, $10, $12 in BCD:
L16BE:  DAA
L16BF:  CMP  B                      ;score above 8999, 10999 or 12999?
L16C0:  JNC  CheckExtraJump         ;Not yet
L16C3:  LXI  H,COINS_PER_GAME       ;The coins this game cost
L16C6:  MOV  A,M
L16C7:  DCX  H
L16C8:  STAX D                      ;BONUS_GAME: awarded
L16C9:  ADD  M                      ;Give them back
L16CA:  MOV  M,A
L16CB:  LXI  H,TxtAdditionalGame    ;"ADDITIONAL GAME"
L16CE:  LXI  D,$3E88                ;Line 212, column 8
L16D1:  MVI  A,$0F
L16D3:  JMP  DrawString

CheckExtraJump:
L16D6:  IN   INP_DIP                ;Extra jump setting
L16D8:  ANI  $20
L16DA:  MVI  C,$03                  ;At 3000
L16DC:  JZ   L16E0
L16DF:  INR  C                      ;or 4000
L16E0:  MOV  A,B                    ;Score thousands
L16E1:  CMP  C
L16E2:  RC                          ;Not there yet
L16E3:  MOV  A,M                    ;This player had it already?
L16E4:  ANA  A
L16E5:  RNZ
L16E6:  INR  M                      ;Now it has
L16E7:  LXI  H,BonusTune            ;Bonus tune
L16EA:  SHLD TUNE_PTR
L16ED:  MVI  A,$5A                  ;Freeze for 90 ticks (3 s)
L16EF:  STA  TMR_FREEZE
L16F2:  STA  FREEZE_REQ
L16F5:  STA  JUMPS_AGAIN            ;JUMPS_AGAIN
L16F8:  LXI  H,TxtBonus             ;"BONUS" in big letters
L16FB:  LXI  D,$3486
L16FE:  MVI  A,$05
L1700:  CALL DrawBigString
L1703:  LXI  H,TxtPlayerJumpsAgain  ;"PLAYER JUMPS AGAIN"
L1706:  LXI  D,$3E87                ;Line 212, column 7
L1709:  MVI  A,$12                  ;18 characters
L170B:  JMP  DrawString

;------------------------------------------------------------------------------
; LaunchXSpeed - A = distance from the middle of the zone (1-3). Returns A = E = X speed, D = launch speed.
;   X speed = (SPEED_LEVEL + 5) x 3 x distance / 16.
;------------------------------------------------------------------------------
LaunchXSpeed:
L170E:  MOV  E,A
L170F:  XRA  A
L1710:  ADI  $03                    ;E = 3 x distance
L1712:  DCR  E
L1713:  JNZ  L1710
L1716:  MOV  E,A
L1717:  LDA  SPEED_LEVEL            ;D = SPEED_LEVEL + 5
L171A:  ADI  $05
L171C:  MOV  D,A
L171D:  XRA  A
L171E:  ADD  D                      ;A = D x E
L171F:  DCR  E
L1720:  JNZ  L171E
L1723:  RRC                         ;/ 16
L1724:  RRC
L1725:  RRC
L1726:  RRC
L1727:  ANI  $0F
L1729:  RET

;------------------------------------------------------------------------------
; ContactAbove - Contact above the seesaw zone: balloon rows, ledges, or nothing.
;------------------------------------------------------------------------------
ContactAbove:
L172A:  CPI  $5C                    ;In the balloon rows (above $5C)?
L172C:  JC   ContactBalloons
L172F:  MOV  A,E                    ;No: flyer X
L1730:  CPI  $18                    ;Within 24 pixels of the left side?
L1732:  JC   LedgeBounce
L1735:  CPI  $D8                    ;or of the right side?
L1737:  JC   ClearContact           ;No: nothing there

;------------------------------------------------------------------------------
; LedgeBounce - The flyer touched a ledge: if it is falling, bounce it up and away from the wall.
;------------------------------------------------------------------------------
LedgeBounce:
L173A:  LHLD FLYER_PTR
L173D:  INX  H
L173E:  INX  H
L173F:  INX  H
L1740:  INX  H
L1741:  CALL ClearContact           ;Contact handled
L1744:  MOV  A,M                    ;YVEL
L1745:  ANA  A
L1746:  RM                          ;Going up: no bounce
L1747:  MVI  M,$FE                  ;2 up
L1749:  DCX  H
L174A:  MOV  A,M                    ;X: which side?
L174B:  ANA  A
L174C:  DCX  H
L174D:  MVI  M,$01                  ;XVEL: 1 right off the left wall,
L174F:  JP   L1754
L1752:  MVI  M,$FF                  ;1 left off the right wall
L1754:  DCX  H
L1755:  MVI  M,$10                  ;Picture $10: crouched
L1757:  RET

;------------------------------------------------------------------------------
; ContactBalloons - Contact above line $5C: find the balloon row by height.
;------------------------------------------------------------------------------
ContactBalloons:
L1758:  MVI  B,$00                  ;Row 0: bottom, Y $4E
L175A:  LXI  H,P1_ROW_BOT
L175D:  MVI  D,$4E
L175F:  CMP  D                      ;Contact at or below the bottom row?
L1760:  JNC  PopBalloon
L1763:  LXI  H,P1_ROW_MID           ;Row 1: middle, Y $38
L1766:  MVI  D,$38
L1768:  INR  B
L1769:  CMP  D
L176A:  JNC  PopBalloon
L176D:  LXI  H,P1_ROW_TOP           ;Row 2: top, Y $24
L1770:  MVI  D,$24
L1772:  INR  B
L1773:  CMP  D
L1774:  JNC  PopBalloon             ;Above the top row: nothing, falls into ClearContact

;------------------------------------------------------------------------------
; ClearContact - CONTACT_ROW = 0: the contact has been dealt with.
;------------------------------------------------------------------------------
ClearContact:
L1777:  XRA  A
L1778:  STA  CONTACT_ROW
L177B:  RET

;------------------------------------------------------------------------------
; PopBalloon - Find the balloon the flyer touched in row HL (B = row number, D = its Y) and pop it.
;   A balloon is hit when its X is within flyer X - 8 .. flyer X + 15. The
;   balloon is removed and blanked; the flyer gets a random tumble picture and
;   bounces: up at 1 if it was falling, down at REBOUND_SPEED if it was rising.
;   Scores 20, 50 or 100 with the matching pop sound.
;------------------------------------------------------------------------------
PopBalloon:
L177C:  MOV  A,B                    ;Remember the row for the score
L177D:  STA  HIT_ROW
L1780:  LDA  PLAYER                 ;Which player's row?
L1783:  ANA  A
L1784:  JZ   L178B
L1787:  LXI  B,P2_OFFSET
L178A:  DAD  B
L178B:  MVI  B,$0C                  ;12 balloons
L178D:  MOV  C,E                    ;C = flyer X
L178E:  MOV  A,M
L178F:  ANA  A
L1790:  JP   NextBalloon            ;Popped already
L1793:  INX  H
L1794:  MOV  A,M
L1795:  DCX  H
L1796:  MOV  E,A                    ;E = balloon X
L1797:  SUB  C                      ;- flyer X
L1798:  ADI  $08                    ;+ 8
L179A:  CPI  $18                    ;Within 24?
L179C:  JNC  NextBalloon            ;No
L179F:  MVI  A,$03                  ;No contact for 3 ticks
L17A1:  STA  TMR_HIT_LOCKOUT
L17A4:  MVI  M,$00                  ;Balloon gone
L17A6:  CALL Random
L17A9:  ANI  $07                    ;Random picture,
L17AB:  INR  A                      ;tumble 1-8
L17AC:  LHLD FLYER_PTR
L17AF:  MVI  M,$A0                  ;In use, blank this picture
L17B1:  INX  H
L17B2:  MOV  M,A                    ;CL_FRAME
L17B3:  INX  H
L17B4:  INX  H
L17B5:  INX  H
L17B6:  MOV  A,M                    ;CL_YVEL
L17B7:  ANA  A
L17B8:  MVI  M,$FF                  ;Bounce up at 1
L17BA:  JP   L17C1                  ;It was falling
L17BD:  LDA  REBOUND_SPEED          ;It was rising: knock it down
L17C0:  MOV  M,A
L17C1:  CALL ScreenAddr             ;Screen address of the balloon (X = E, Y = D)
L17C4:  MVI  C,$1F                  ;To the next line: 32 - 1
L17C6:  XCHG
L17C7:  MVI  A,$08                  ;8 rows
L17C9:  MOV  M,B                    ;Blank its two bytes
L17CA:  INX  H
L17CB:  MOV  M,B
L17CC:  DAD  B
L17CD:  DCR  A
L17CE:  JNZ  L17C9
L17D1:  STA  CONTACT_ROW            ;A = 0: contact handled
L17D4:  LDA  GAME_ACTIVE            ;Game on?
L17D7:  ANA  A
L17D8:  RZ
L17D9:  LDA  HIT_ROW                ;Row popped
L17DC:  MOV  C,A
L17DD:  LXI  H,PopTable             ;Points and sound per row
L17E0:  DAD  B
L17E1:  DAD  B
L17E2:  MOV  C,M                    ;C = points / 10
L17E3:  INX  H
L17E4:  MOV  A,M
L17E5:  OUT  OUT_SOUND              ;Pop sound
L17E7:  MVI  A,$07                  ;for 7 ticks
L17E9:  STA  TMR_SOUND_OFF
L17EC:  JMP  AddScore               ;Add the points (B = 0)

NextBalloon:
L17EF:  INX  H
L17F0:  INX  H
L17F1:  INX  H
L17F2:  DCR  B
L17F3:  JNZ  L178E
L17F6:  JMP  ClearContact           ;No balloon there

;------------------------------------------------------------------------------
; PopTable - Per row (bottom, middle, top): points / 10 in BCD, OUT_SOUND value.
;------------------------------------------------------------------------------
PopTable:
L17F9:  .byte $02, $09              ;bottom row: 20 points, OUT_SOUND value
L17FB:  .byte $05, $0A              ;middle row: 50 points, OUT_SOUND value
L17FD:  .byte $10, $0C              ;top row: 100 points, OUT_SOUND value
L17FF:  .byte $00                   ;unused
