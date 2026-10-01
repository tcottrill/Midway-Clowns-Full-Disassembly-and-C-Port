/* plat_headless.c - the quiet backend (see plat_headless.h). */
#include <string.h>
#include "plat_headless.h"

plat_inputs   plat_headless_in;
uint8_t       plat_headless_dsw;
uint8_t       plat_headless_frame[PLAT_VIDEO_BYTES];
unsigned long plat_headless_audio_frames;

int  plat_init(void) { return 0; }
void plat_shutdown(void) {}

void plat_video_present(const uint8_t *bitmap)
{
    memcpy(plat_headless_frame, bitmap, PLAT_VIDEO_BYTES);
}

void plat_input_poll(plat_inputs *in)
{
    *in = plat_headless_in;
    plat_headless_in.reset = 0;
}

uint8_t plat_dsw(void) { return plat_headless_dsw; }

int  plat_audio_open(int sample_rate) { (void)sample_rate; return 0; }
void plat_audio_push(const int16_t *pcm, int frames) { (void)pcm; plat_headless_audio_frames += (unsigned long)frames; }
void plat_audio_close(void) {}

void plat_status_text(const char *s) { (void)s; }
