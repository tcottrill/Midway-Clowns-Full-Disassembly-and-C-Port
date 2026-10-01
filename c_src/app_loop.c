/* app_loop.c - the native seam: the machine around the translated program.
 *
 * It implements hw.h (the ports) over the platform contract and runs the
 * machine one frame at a time on a timeline counted in 8080 cycles.
 *
 * The board (MAME mw8080bw): 19.968 MHz crystal, CPU at /10 = 1.9968 MHz, 262
 * lines of 128 CPU cycles = 33536 cycles a frame, 59.54 frames a second.  The
 * vertical counter raises an interrupt at line 224 (the start of vblank, RST 2)
 * and at line 96 (RST 1).
 *
 * The 8080 is in one of four endless loops (g.cpu_loop).  One trip round a
 * loop is one C call (a "pass") and is not interruptible here, so the seam
 * keeps the two interrupts on their exact times and lets passes fill the time
 * in between:
 *
 *   - each event is charged the cycles the ROM spends on it (pass_cost,
 *     irq_cost: means measured on the real ROM with tests\lockstep --costs),
 *     which gives the main loop its real rate - about one pass per interrupt
 *     period in a game, eighteen in attract mode;
 *   - with interrupts enabled, an interrupt is taken exactly at its time,
 *     between two passes or while the time of a pass is still running (the
 *     pass's work was done when it started);
 *   - while the ROM has interrupts disabled (it runs its script commands that
 *     way, and CLEAR alone takes 1.4 frames) a raised interrupt waits for the
 *     next EI; a second one raised meanwhile is lost, as on the board, and the
 *     one that is finally taken gets the vector of the beam position at that
 *     moment (MAME: bit 6 of the vertical counter).
 *
 * What this does not reproduce: an interrupt landing between two instructions
 * of a pass.  A pass is atomic here, so the interrupt sees either all of its
 * work or none.
 */
#include <string.h>
#include "state.h"
#include "hw.h"
#include "game.h"
#include "sound.h"
#include "platform/clowns_platform.h"

#define SAMPLE_RATE      44100
#define WATCHDOG_FRAMES  255       /* MAME: the watchdog bites after 255 frames without a kick */

#define LINE_CYCLES      128
#define FRAME_LINES      262
#define FRAME_CYCLES     (FRAME_LINES * LINE_CYCLES)      /* 33536 */
#define VBLANK_LINE      224                              /* RST 2 */
#define MID_LINE         96                               /* RST 1 */
#define PERIOD_A         ((FRAME_LINES - VBLANK_LINE + MID_LINE) * LINE_CYCLES)   /* line 224 -> 96 */

static plat_inputs      in;
static uint8_t          out_misc;           /* last OUT_MISC value */
static int              watchdog_frames;
static int              audio_ok;
static double           sample_frac;        /* audio samples owed, fractional part */
static clowns_app_stats stats;

static uint64_t         now;                /* machine time the foreground has used up, CPU cycles */
static uint64_t         pass_start;         /* when the last pass began */
static uint64_t         frame_start;        /* time of this frame's line 224 */
static int              pending;            /* an interrupt is raised and not taken */
static int              pending_which;      /* 1 = RST 1, 2 = RST 2 as raised */
static int              pending_held;       /* it found interrupts disabled */

/* ---- hw.h ----------------------------------------------------------------- */
uint8_t hw_in_paddle(void)
{
    return in.paddle[(out_misc >> 1) & 1];                 /* OUT_MISC b1 selects the paddle */
}

uint8_t hw_in_switch(void)
{
    uint8_t v = 0xFF;                                      /* active low; unused bits read 1 */
    if (in.start2) v &= (uint8_t)~0x10;
    if (in.start1) v &= (uint8_t)~0x20;
    if (in.coin)   v &= (uint8_t)~0x40;
    return v;
}

uint8_t hw_in_dip(void)
{
    return (uint8_t)((plat_dsw() & 0x7F) | (in.test ? 0x80 : 0x00));
}

void hw_out_misc(uint8_t v) { out_misc = v; }              /* b0 coin counter (not modelled), b1 paddle select */
void hw_watchdog(void)      { watchdog_frames = 0; }
void hw_tone_lo(uint8_t v)  { sound_tone_lo(v); }
void hw_tone_hi(uint8_t v)  { sound_tone_hi(v); }
void hw_sound(uint8_t v)    { sound_port(v); }

/* ---- what the ROM spends, in 8080 cycles -----------------------------------
 * Means of the real ROM's events, measured by tests\lockstep.exe --costs over
 * attract mode and one- and two-player games.  A model, not a count: it sets
 * how many passes fit between two interrupts, nothing else. */
static uint32_t pass_cost(void)
{
    uint16_t sp;
    uint8_t  op, n;

    switch (g.cpu_loop) {
    case LOOP_SELF_TEST:      return 21266598u;            /* one RAM + ROM test: 10.6 s */
    case LOOP_SELF_TEST_WAIT: return 44u;
    case LOOP_SWITCH_TEST:    return 63644u;
    default: break;
    }
    sp = rd16(A_SCRIPT_PTR);
    op = cpu_rd(sp);
    n = cpu_rd((uint16_t)(sp + 1));
    switch (op) {
    case 0x00:                                             /* WAIT: the game tasks */
        return 800u + (PLAYFIELD_ON ? 1300u : 0u) + (GAME_ACTIVE ? 6900u : 0u);
    case 0x02: return 100u + 1320u * n;                    /* TEXT, per character */
    case 0x10: return 200u + 5950u * n;                    /* BIGTEXT, per character */
    case 0x0C: return 30u + 192u * (n ? n : 256u);         /* CLEAR, per 32 bytes */
    case 0x0E: return 6300u;                               /* SCORE */
    case 0x18: return 1125u;                               /* ROW */
    default:   return 250u;                                /* DELAY, GOTO, SET, IFZ ... */
    }
}

static uint32_t irq_cost(uint8_t frame_before, int could_update)
{
    int on_screen = (SEESAW_STATE & 0x80) != 0;
    if (FRAME_CTR == frame_before)                         /* the flyer's interrupt */
        return could_update ? 8000u : 500u;
    if (FRAME_CTR & 1)                                     /* odd frame: balloons, timers */
        return on_screen ? 5000u : 1300u;
    return on_screen ? 8300u : 470u;                       /* even frame: seesaw, rider */
}

/* ---- the machine ---------------------------------------------------------- */
static void power_on(void)
{
    memset(&g, 0, sizeof g);
    out_misc = 0;
    watchdog_frames = 0;
    pending = 0;
    sound_reset(SAMPLE_RATE);
    stats.resets++;
    reset();
}

static void run_pass(void)
{
    uint32_t cost = pass_cost();
    uint8_t  loop = g.cpu_loop;
    pass_start = now;
    switch (loop) {
    case LOOP_MAIN:           main_loop_pass(); stats.passes++; break;
    case LOOP_SELF_TEST:      self_test_pass(); break;
    case LOOP_SELF_TEST_WAIT: self_test_wait_pass(); break;
    default:                  switch_test_pass(); break;
    }
    if (loop == LOOP_SELF_TEST && g.cpu_loop == LOOP_SWITCH_TEST)
        cost = 49082u;                                     /* coin held: left at once, cleared RAM */
    now += cost;
}

static void take_interrupt(void)
{
    int     which = pending_which;
    uint8_t frame_before = FRAME_CTR;
    int     could_update = FREEZE == 0 && CONTACT_ROW == 0 && (cpu_rd(rd16(A_FLYER_PTR)) & 0x80);

    if (pending_held) {
        /* taken late, at the EI that starts a WAIT pass: the vector is the beam's at that moment */
        uint64_t t = pass_start > frame_start ? pass_start : frame_start;
        unsigned line = (unsigned)((VBLANK_LINE + (t - frame_start) / LINE_CYCLES) % FRAME_LINES);
        unsigned counter = line < VBLANK_LINE ? line + 0x20u : 0xDAu + (line - VBLANK_LINE);
        which = (counter & 0x40) ? 2 : 1;
        stats.irqs_held++;
    }
    pending = 0;
    g.iff = 0;                                             /* taking an interrupt disables them */
    g.irq_count++;
    stats.irqs++;
    if (which == 1) rst1(); else rst2();                   /* both leave through IrqExit: EI */
    now += irq_cost(frame_before, could_update);
}

/* Raise an interrupt now and run the foreground up to machine time `end`.
 * With interrupts enabled it is taken at once - also when the foreground is
 * still paying for a long pass (`now` beyond this moment): on the board it
 * would land in the middle of that pass; here the pass's work is already done
 * and only its time is still running.  The handler's cycles are taken from the
 * foreground. */
static void run_period(int which, uint64_t end)
{
    if (pending) stats.irqs_lost++;                        /* the latch holds only one */
    pending = 1;
    pending_which = which;
    pending_held = !g.iff;
    if (g.iff) take_interrupt();
    while (now < end) {
        run_pass();
        if (pending && g.iff) take_interrupt();            /* the EI after script commands */
    }
}

static void render_audio(double frames_of_time)
{
    int16_t buf[1024];
    int     n;
    sample_frac += frames_of_time * SAMPLE_RATE / CLOWNS_FRAME_HZ;
    n = (int)sample_frac;
    sample_frac -= n;
    if (n > (int)(sizeof buf / sizeof buf[0])) n = (int)(sizeof buf / sizeof buf[0]);
    if (n <= 0) return;
    sound_render(buf, n);
    if (audio_ok) plat_audio_push(buf, n);
}

void clowns_app_init(void)
{
    memset(&stats, 0, sizeof stats);
    memset(&in, 0, sizeof in);
    in.paddle[0] = in.paddle[1] = 0x7F;
    now = frame_start = 0;
    plat_input_poll(&in);                                  /* the self-test switch is read at reset */
    audio_ok = plat_audio_open(SAMPLE_RATE) == 0;
    power_on();
}

void clowns_app_frame(void)
{
    plat_input_poll(&in);
    if (in.reset) power_on();
    if (now >= frame_start + FRAME_CYCLES) watchdog_frames = 0;   /* inside a long pass (the RAM test kicks it all the time) */
    if (++watchdog_frames > WATCHDOG_FRAMES) power_on();   /* nothing kicked the watchdog */

    plat_video_present(&g.ram[A_VideoRam - A_WorkRam]);
    run_period(2, frame_start + PERIOD_A);                 /* line 224: vblank; up to line 96 */
    render_audio((double)PERIOD_A / FRAME_CYCLES);
    run_period(1, frame_start + FRAME_CYCLES);             /* line 96: mid-screen; up to line 224 */
    render_audio((double)(FRAME_CYCLES - PERIOD_A) / FRAME_CYCLES);
    frame_start += FRAME_CYCLES;
    stats.frames++;
}

void clowns_app_exit(void)
{
    if (audio_ok) plat_audio_close();
    audio_ok = 0;
}

void clowns_app_get_stats(clowns_app_stats *s)
{
    stats.loop = g.cpu_loop;
    stats.machine_cycles = now;
    *s = stats;
}
