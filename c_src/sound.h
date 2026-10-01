/* sound.h - the Clowns sound board, as a synthesizer.
 *
 * The tone generator is modelled from its counter (the pitch is exact); the
 * discrete sounds (balloon pops, springboard hit) and the miss sound (a sample
 * in MAME) are approximations by ear of what the circuits do, not circuit
 * models.  app_loop.c forwards the three sound ports here and renders the
 * stream twice a frame.
 */
#ifndef SOUND_H
#define SOUND_H

#include <stdint.h>

void sound_reset(int sample_rate);
void sound_tone_lo(uint8_t v);     /* OUT 5: b0 enable, b1-b5 low preset bits */
void sound_tone_hi(uint8_t v);     /* OUT 6: b0-b5 high preset bits */
void sound_port(uint8_t v);        /* OUT 7: b0-b2 pops, b3 enable, b4 hit, b5 miss */
void sound_set_volume(int percent);
void sound_render(int16_t *out, int frames);

#endif /* SOUND_H */
