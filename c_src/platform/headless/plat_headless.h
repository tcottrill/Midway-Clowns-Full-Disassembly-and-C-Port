/* plat_headless.h - the quiet backend: no window, no sound, no clock.
 * A test drives the inputs through these and takes the picture it is given. */
#ifndef PLAT_HEADLESS_H
#define PLAT_HEADLESS_H

#include <stdint.h>
#include "../clowns_platform.h"

/* The inputs the next plat_input_poll returns (reset is cleared after one poll). */
extern plat_inputs plat_headless_in;
/* INP_DIP b0-b6. */
extern uint8_t     plat_headless_dsw;
/* The last picture presented (PLAT_VIDEO_BYTES). */
extern uint8_t     plat_headless_frame[PLAT_VIDEO_BYTES];
/* Audio frames pushed so far. */
extern unsigned long plat_headless_audio_frames;

#endif /* PLAT_HEADLESS_H */
