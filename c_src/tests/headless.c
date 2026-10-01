/* headless.c - run the port without a window: scripted inputs, PNG shots.
 *
 *   clowns_headless [options]
 *     --frames N            run N frames (default 600)
 *     --shot F FILE.png     save the picture of frame F (repeatable, up to 32)
 *     --coin F              press the coin switch for 6 frames from frame F (repeatable)
 *     --start1 F / --start2 F   press a start button for 6 frames from frame F
 *     --paddle V            hold both paddles at V (0-255)
 *     --track               steer the seesaw under the flyer, the way the ROM's
 *                           own attract autopilot does (reads the machine state)
 *     --dip N               option switches INP_DIP b0-b6 (hex or decimal)
 *     --test                self-test switch on at power-on
 *     --dump FILE           write RAM $2000-$3FFF at the end
 *     --trace               print the script pointer and scores once a second
 *
 * Prints a summary: frames, passes, interrupts, the scores and a checksum of
 * RAM, so two runs can be compared.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../state.h"
#include "../shot.h"
#include "../platform/headless/plat_headless.h"

#define MAX_EVENTS 32

typedef struct { long frame; const char *file; } shot_t;
typedef struct { long frame; int what; } press_t;   /* what: 0 coin, 1 start1, 2 start2 */

static uint32_t fnv(const uint8_t *p, size_t n)
{
    uint32_t h = 2166136261u;
    while (n--) { h ^= *p++; h *= 16777619u; }
    return h;
}

int main(int argc, char **argv)
{
    shot_t  shots[MAX_EVENTS];
    press_t presses[MAX_EVENTS];
    int     nshots = 0, npresses = 0, track = 0, trace = 0, paddle = 0x7F, i;
    long    frames = 600, f;
    const char *dump = NULL;
    clowns_app_stats st;

    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--frames") && i + 1 < argc) frames = atol(argv[++i]);
        else if (!strcmp(argv[i], "--shot") && i + 2 < argc && nshots < MAX_EVENTS) {
            shots[nshots].frame = atol(argv[++i]);
            shots[nshots++].file = argv[++i];
        }
        else if (!strcmp(argv[i], "--coin") && i + 1 < argc && npresses < MAX_EVENTS) {
            presses[npresses].frame = atol(argv[++i]); presses[npresses++].what = 0;
        }
        else if (!strcmp(argv[i], "--start1") && i + 1 < argc && npresses < MAX_EVENTS) {
            presses[npresses].frame = atol(argv[++i]); presses[npresses++].what = 1;
        }
        else if (!strcmp(argv[i], "--start2") && i + 1 < argc && npresses < MAX_EVENTS) {
            presses[npresses].frame = atol(argv[++i]); presses[npresses++].what = 2;
        }
        else if (!strcmp(argv[i], "--paddle") && i + 1 < argc) paddle = atoi(argv[++i]) & 0xFF;
        else if (!strcmp(argv[i], "--track")) track = 1;
        else if (!strcmp(argv[i], "--trace")) trace = 1;
        else if (!strcmp(argv[i], "--dip") && i + 1 < argc) plat_headless_dsw = (uint8_t)strtol(argv[++i], NULL, 0);
        else if (!strcmp(argv[i], "--test")) plat_headless_in.test = 1;
        else if (!strcmp(argv[i], "--dump") && i + 1 < argc) dump = argv[++i];
        else { fprintf(stderr, "unknown option %s\n", argv[i]); return 2; }
    }

    plat_headless_in.paddle[0] = plat_headless_in.paddle[1] = (uint8_t)paddle;
    plat_init();
    clowns_app_init();

    for (f = 0; f < frames; f++) {
        plat_headless_in.coin = plat_headless_in.start1 = plat_headless_in.start2 = 0;
        for (i = 0; i < npresses; i++) {
            if (f >= presses[i].frame && f < presses[i].frame + 6) {
                if (presses[i].what == 0) plat_headless_in.coin = 1;
                if (presses[i].what == 1) plat_headless_in.start1 = 1;
                if (presses[i].what == 2) plat_headless_in.start2 = 1;
            }
        }
        if (track) {
            /* what Autopilot ($0CE5) computes, fed in as the paddle */
            uint16_t fl = rd16(A_FLYER_PTR);
            if (cpu_rd(fl) & 0x80) {
                uint8_t x = cpu_rd((uint16_t)(fl + K_CL_X));
                uint8_t a = (uint8_t)(((SEESAW_STATE & 0x20) ? 0xFC : 0xE8) + x);
                if (a >= 0xE0) a = (uint8_t)(((uint8_t)(x + 1) & 0x80) ? 0xD7 : 0x00);
                plat_headless_in.paddle[0] = plat_headless_in.paddle[1] = a;
            }
        }
        clowns_app_frame();
        for (i = 0; i < nshots; i++) {
            if (shots[i].frame == f) {
                if (shot_write_png(shots[i].file, plat_headless_frame, 2)) {
                    fprintf(stderr, "cannot write %s\n", shots[i].file);
                    return 1;
                }
            }
        }
        if (trace && f % 60 == 0)
            printf("frame %5ld  script $%04X  game %d  player %02X  jumps %d  P1 %02X%02X0  P2 %02X%02X0  coins %d\n",
                   f, rd16(A_SCRIPT_PTR), GAME_ACTIVE, PLAYER, JUMPS_LEFT,
                   g.ram[A_P1_SCORE - 0x2000], g.ram[A_P1_SCORE + 1 - 0x2000],
                   g.ram[A_P2_SCORE - 0x2000], g.ram[A_P2_SCORE + 1 - 0x2000], COINS);
    }

    clowns_app_get_stats(&st);
    printf("frames %lu  passes %lu (%.2f per frame)  irqs %lu  taken late %lu  lost %lu  resets %lu  loop %d\n",
           st.frames, st.passes, st.frames ? (double)st.passes / st.frames : 0.0,
           st.irqs, st.irqs_held, st.irqs_lost, st.resets, st.loop);
    printf("script $%04X  game %d  P1 %02X%02X0  P2 %02X%02X0  high %02X%02X0  stray writes %u\n",
           rd16(A_SCRIPT_PTR), GAME_ACTIVE,
           g.ram[A_P1_SCORE - 0x2000], g.ram[A_P1_SCORE + 1 - 0x2000],
           g.ram[A_P2_SCORE - 0x2000], g.ram[A_P2_SCORE + 1 - 0x2000],
           g.ram[A_HI_SCORE - 0x2000], g.ram[A_HI_SCORE + 1 - 0x2000], (unsigned)g.stray_writes);
    if (g.stray_writes) printf("last stray write at $%04X\n", (unsigned)g.stray_addr);
    printf("ram checksum %08X  audio frames %lu\n", (unsigned)fnv(g.ram, sizeof g.ram), plat_headless_audio_frames);
    if (dump) {
        FILE *fp = fopen(dump, "wb");
        if (!fp || fwrite(g.ram, 1, sizeof g.ram, fp) != sizeof g.ram) { fprintf(stderr, "cannot write %s\n", dump); return 1; }
        fclose(fp);
    }
    clowns_app_exit();
    plat_shutdown();
    return 0;
}
