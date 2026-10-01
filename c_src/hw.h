/* hw.h - the hardware seam for the Clowns C port.
 *
 * Translated code touches the outside world ONLY through these calls.
 * Implementations:
 *   app_loop.c          the game (platform layer behind it)
 *   tests/lockstep.c    answers reads with what the real ROM read at the same
 *                       point of the same run, and checks the writes
 * Port names are the defines file's.  The MB14241 shifter (ports 1-3) is part
 * of the machine state instead (state.h).
 */
#ifndef HW_H
#define HW_H

#include <stdint.h>

/* ---- inputs ------------------------------------------------------------- */
uint8_t hw_in_paddle(void);        /* IN 0  INP_PADDLE: paddle of the player OUT_MISC b1 selects */
uint8_t hw_in_switch(void);        /* IN 1  INP_SWITCH: b4 start 2, b5 start 1, b6 coin; active low */
uint8_t hw_in_dip(void);           /* IN 2  INP_DIP: option switches, b7 self test */

/* ---- outputs ------------------------------------------------------------ */
void    hw_out_misc(uint8_t v);    /* OUT 3 OUT_MISC: b0 coin counter, b1 paddle select */
void    hw_watchdog(void);         /* OUT 4 OUT_WATCHDOG */
void    hw_tone_lo(uint8_t v);     /* OUT 5 OUT_TONE_LO: b0 enable, b1-b5 low period bits */
void    hw_tone_hi(uint8_t v);     /* OUT 6 OUT_TONE_HI: b0-b5 high period bits */
void    hw_sound(uint8_t v);       /* OUT 7 OUT_SOUND: pops, enable, hit, miss */

#endif /* HW_H */
