/* clowns_platform.h - the platform contract for the Clowns C port.
 *
 * The core (the translated modules, sound.c and app_loop.c, the game seam) is
 * platform-agnostic and calls ONLY these functions for video, input, audio,
 * time and settings.  Each backend under platform/<name>/ implements the whole
 * contract in plain C; the build links exactly one backend per binary.
 *
 * Backends:
 *   windows/   plat_win.c: window, GDI blit, waveOut audio, mouse / keyboard
 *              -> clowns_win.exe (build_win.bat)
 *   headless/  plat_headless.c: scripted inputs, PNG shots, no audio, no clock
 *              -> tests\clowns_headless.exe (build_all.bat)
 *
 * Hardware truth (which port bit means what, polarity, interrupt timing) lives
 * in app_loop.c.  Key bindings are backend policy.
 */
#ifndef CLOWNS_PLATFORM_H
#define CLOWNS_PLATFORM_H

#include <stdint.h>

/* ---- lifecycle --------------------------------------------------------- */
int  plat_init(void);            /* 0 = ok */
void plat_shutdown(void);

/* ---- video ---------------------------------------------------------------
 * The game's own bitmap, once per frame: 224 lines of 32 bytes, the bytes of
 * video RAM $2400-$3FFF in address order; bit 0 of a byte is its leftmost
 * pixel, a set bit is lit.  The picture is 256 x 224, not rotated. */
#define PLAT_VIDEO_W     256
#define PLAT_VIDEO_H     224
#define PLAT_VIDEO_BYTES (32 * 224)
void plat_video_present(const uint8_t *bitmap);

/* ---- input ---------------------------------------------------------------
 * Polled once per frame by app_loop.c, which encodes the ports:
 *   paddle[0], paddle[1]  the two players' paddles, 0-255 (IN 0; the game
 *                         selects which one it reads with OUT_MISC b1)
 *   coin start1 start2    1 = pressed (the core inverts: IN 1 is active low)
 *   test                  the self-test switch (INP_DIP b7), a latching switch;
 *                         the ROM only looks at it at reset and in the self test
 *   reset                 1 = power-cycle the machine now (host affordance)
 *   quit                  host affordance, never reaches the machine */
typedef struct {
    uint8_t paddle[2];
    uint8_t coin, start1, start2;
    uint8_t test;
    uint8_t reset;
    uint8_t quit;
} plat_inputs;

void plat_input_poll(plat_inputs *in);

/* Option switches, raw as INP_DIP reads them (b7 comes from plat_inputs.test):
 *   b0-b1 coinage: 0 = 1 coin 1 player, 1 = 1 coin 2 players,
 *                  2 = 2 coins 2 players, 3 = 2 coins per player
 *   b2-b3 bonus game: 0 none, 1 at 9000, 2 at 11000, 3 at 13000
 *   b4    balloon resets: 0 each row, 1 all rows
 *   b5    extra jump: 0 at 3000, 1 at 4000
 *   b6    jumps per game: 0 = 3, 1 = 4 */
uint8_t plat_dsw(void);

/* ---- audio ---------------------------------------------------------------
 * One mono signed 16-bit stream, pushed twice per frame (after each of the
 * two interrupt periods).  plat_audio_open returns 0 when the stream is up. */
int  plat_audio_open(int sample_rate);
void plat_audio_push(const int16_t *pcm, int frames);
void plat_audio_close(void);

/* ---- misc ---------------------------------------------------------------- */
void plat_status_text(const char *s);    /* about once a second; may be a no-op */

/* ---- app hooks: what a backend's main loop calls (app_loop.c) ------------
 *   clowns_app_init()   power on: clear the machine, run the ROM's reset path
 *   clowns_app_frame()  poll inputs and run one frame of machine time (33536
 *                       CPU cycles, 59.54 Hz on the board): the vblank
 *                       interrupt, main-loop passes, the mid-screen interrupt,
 *                       main-loop passes; presents the picture and pushes the
 *                       frame's audio.  The backend paces the calls.
 *   clowns_app_exit()   close audio */
void clowns_app_init(void);
void clowns_app_frame(void);
void clowns_app_exit(void);

/* The board's frame rate: 19.968 MHz / 4 / (320 x 262). */
#define CLOWNS_FRAME_HZ 59.541985

/* Counters for a backend's status line / log (cumulative since power-on). */
typedef struct {
    unsigned long frames;
    unsigned long passes;        /* main-loop passes */
    unsigned long irqs;          /* interrupts serviced */
    unsigned long irqs_held;     /* of those, taken late: raised while the ROM had them disabled */
    unsigned long irqs_lost;     /* raised while one was still waiting */
    unsigned long resets;        /* reset() calls, power-on included */
    uint64_t      machine_cycles;/* machine time in CPU cycles */
    int           loop;          /* LOOP_* the CPU is in */
} clowns_app_stats;
void clowns_app_get_stats(clowns_app_stats *s);

#endif /* CLOWNS_PLATFORM_H */
