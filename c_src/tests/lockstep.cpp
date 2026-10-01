// lockstep.cpp - the C port against the real ROM, event by event.
//
// The oracle is the program ROM (progrom.c, generated from the ROM set) on an
// Intel 8080 interpreter - AAE's cpu_i8080 (tests\i8080\, Mike Chambers' core
// as converted for AAE; copied here unchanged) - with the board modelled around
// it: RAM and its mirror, the MB14241 shifter, the input and output ports.
//
// Both machines are driven through the same sequence of events, the one
// app_loop.c produces: per frame the vblank interrupt, main-loop passes, the
// mid-screen interrupt, main-loop passes.  On the oracle an event runs from one
// of the ROM's loop heads to the next:
//
//     $0A51 MainLoop        one pass = until PC is back at $0A51
//     $0022 RamTest         one self-test pass (RAM + ROM test)
//     $011F SelfTestWait    one trip
//     $134D SwitchTest      one trip
//     interrupt             RST 1 / RST 2 taken at the loop head, until it
//                           returns there
//
// and on the port it is one call (main_loop_pass, rst1, ...).  After EVERY
// event the two are compared: all RAM except the stack page, the interrupt
// enable, the shifter, which loop the CPU is in, and the exact sequence of
// port writes the event made.  Inputs are scripted and identical on both.
//
// What this proves: every translated routine the scenario reaches computes
// what the ROM computes, byte for byte, video RAM included.  What it does not:
// interrupts that land in the middle of a main-loop pass (the port never does
// that; see README.md).
//
//   lockstep [--frames N] [--coin F] [--start1 F] [--start2 F] [--paddle V]
//            [--track] [--track-frames FROM TO] [--dip N] [--test] [--testoff F]
//            [--passes N] [--quiet] [--trace] [--costs] [--coverage FILE] [--shot F FILE.png]
//     --coin / --start1 / --start2 F   press for 6 frames from frame F (repeatable)
//     --paddle V                       hold both paddles at V
//     --track                          steer the seesaw under the flyer, as the ROM's
//                                      own attract autopilot would
//     --track-frames FROM TO           the same, only in those frames (repeatable)
//     --dip N                          INP_DIP b0-b6;  --test: self-test switch on,
//                                      --testoff F: off again from frame F
//     --passes N                       main-loop passes per interrupt period (default 4)
//     --costs                          print the ROM's 8080 cycles per kind of event
//     --coverage FILE                  OR the ROM addresses executed into FILE (6144
//                                      bytes); tools\coverage.py reports on it
//   lockstep --free ...      the oracle alone with cycle-timed interrupts:
//                            passes per interrupt period, [--shot F FILE.png]
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

extern "C" {
#include "../state.h"
#include "../hw.h"
#include "../game.h"
#include "../shot.h"
}
#include "i8080/cpu_i8080.h"

// ---- scripted inputs, shared by both machines ------------------------------
static uint8_t in_paddle[2] = { 0x7F, 0x7F };
static uint8_t in_switch = 0xFF;          // IN 1, active low
static uint8_t in_dip = 0x00;             // IN 2

// ---- port write logs --------------------------------------------------------
struct OutEv { uint8_t port, val; };
static std::vector<OutEv> o_outs, c_outs;

// ---- the oracle machine -----------------------------------------------------
static uint8_t  orom[0x2000];             // $0000-$17FF ROM, $1800-$1FFF empty (0)
static uint8_t  oram[0x2000];             // $2000-$3FFF
static uint8_t  odummy[0x10000];
static uint16_t o_shift_data;
static uint8_t  o_shift_count;
static uint8_t  o_out_misc;
static unsigned long o_stray, o_instr;
static unsigned long long o_cycles;
static cpu_i8080 *cpu;

// The board decodes 15 address bits: A13 = 0 ROM space ($0000-$1FFF, $4000-$5FFF;
// writes ignored, empty addresses read 0), A13 = 1 RAM ($2000-$3FFF, $6000-$7FFF).
static UINT8 o_mem_read(UINT32 addr, MemoryReadByte *)
{
    addr &= 0x7FFF;
    if (addr & 0x2000) return oram[addr & 0x1FFF];
    return addr < PROGROM_SIZE ? orom[addr] : 0;
}

static void o_mem_write(UINT32 addr, UINT8 v, MemoryWriteByte *)
{
    addr &= 0x7FFF;
    if (addr & 0x2000) oram[addr & 0x1FFF] = v;
    else o_stray++;
}

static MemoryReadByte o_read[] = {
    { 0x0000, 0xFFFF, o_mem_read, nullptr },
    { 0xffffffff, 0xffffffff, nullptr, nullptr }
};
static MemoryWriteByte o_write[] = {
    { 0x0000, 0xFFFF, o_mem_write, nullptr },
    { 0xffffffff, 0xffffffff, nullptr, nullptr }
};

static UINT16 o_port_in(UINT16 port, z80PortRead *)
{
    switch (port & 3) {                                   // ports repeat every 4
    case 0:  return in_paddle[(o_out_misc >> 1) & 1];
    case 1:  return in_switch;
    case 2:  return in_dip;
    default: return (uint8_t)(o_shift_data >> o_shift_count);   // MB14241 result
    }
}

static void o_port_out(UINT16 port, UINT8 val, z80PortWrite *)
{
    switch (port & 7) {
    case 1: o_shift_count = (uint8_t)(~val & 0x07); return;
    case 2: o_shift_data = (uint16_t)((o_shift_data >> 8) | ((uint16_t)val << 7)); return;
    case 3: o_out_misc = val; break;
    default: break;
    }
    o_outs.push_back({ (uint8_t)(port & 7), val });
}

static z80PortRead  o_pin[]  = { { 0x00, 0xFF, o_port_in, nullptr },  { 0xffff, 0xffff, nullptr, nullptr } };
static z80PortWrite o_pout[] = { { 0x00, 0xFF, o_port_out, nullptr }, { 0xffff, 0xffff, nullptr, nullptr } };

static uint8_t coverage[PROGROM_SIZE];   // ROM addresses the oracle executed an instruction at

static void oracle_step()
{
    if (cpu->reg_PC < PROGROM_SIZE) coverage[cpu->reg_PC] = 1;
    int left = cpu->exec(1);                              // exactly one instruction
    o_cycles += (unsigned long long)(1 - left);
    o_instr++;
}

static bool is_sync(uint16_t pc)
{
    return pc == R_MainLoop || pc == R_RamTest || pc == R_SelfTestWait || pc == 0x134D;
}

static int loop_of(uint16_t pc)
{
    if (pc == R_MainLoop) return LOOP_MAIN;
    if (pc == R_RamTest) return LOOP_SELF_TEST;
    if (pc == R_SelfTestWait) return LOOP_SELF_TEST_WAIT;
    return LOOP_SWITCH_TEST;
}

static void oracle_run_to_sync()
{
    unsigned long n = 0;
    do {
        oracle_step();
        if (++n > 400000000ul) {
            std::printf("LOCKSTEP: FAIL - the oracle never came back to a loop head (PC $%04X)\n", cpu->reg_PC);
            std::exit(1);
        }
    } while (!is_sync(cpu->reg_PC));
}

static void oracle_power_on()
{
    std::memset(oram, 0, sizeof oram);
    std::memset(orom, 0, sizeof orom);
    std::memcpy(orom, progrom, PROGROM_SIZE);
    o_shift_data = 0; o_shift_count = 0; o_out_misc = 0;
    cpu = new cpu_i8080(odummy, o_read, o_write, o_pin, o_pout, 0);
    cpu->mame_memory_handling(true);
    cpu->reset();
    cpu->INTE = 0;
}

// ---- the port's seam (hw.h) --------------------------------------------------
static uint8_t c_out_misc;
extern "C" {
uint8_t hw_in_paddle(void) { return in_paddle[(c_out_misc >> 1) & 1]; }
uint8_t hw_in_switch(void) { return in_switch; }
uint8_t hw_in_dip(void)    { return in_dip; }
void    hw_out_misc(uint8_t v) { c_out_misc = v; c_outs.push_back({ 3, v }); }
void    hw_watchdog(void)      { c_outs.push_back({ 4, 0 }); }
void    hw_tone_lo(uint8_t v)  { c_outs.push_back({ 5, v }); }
void    hw_tone_hi(uint8_t v)  { c_outs.push_back({ 6, v }); }
void    hw_sound(uint8_t v)    { c_outs.push_back({ 7, v }); }
}

// ---- comparison -------------------------------------------------------------
static unsigned long events, ev_pass, ev_irq, ev_held;
static unsigned long long bytes_compared;
static long cur_frame;
static const char *coverage_file;
static bool quiet, trace;
static long trace_every = 300;

// The stack page is the one part of RAM the port does not model.
static bool compared(unsigned off) { return off < 0x0300 || off >= 0x0400; }

static void fail_report(const char *what, const char *why)
{
    std::printf("LOCKSTEP: FAIL at event %lu (frame %ld, %s): %s\n", events, cur_frame, what, why);
    std::printf("  oracle PC $%04X SP $%04X INTE %d   port loop %d iff %d\n",
                cpu->reg_PC, cpu->reg_SP, cpu->INTE, g.cpu_loop, g.iff);
    int shown = 0;
    for (unsigned off = 0; off < 0x2000 && shown < 24; off++) {
        if (compared(off) && oram[off] != g.ram[off]) {
            std::printf("  $%04X: ROM %02X  port %02X\n", 0x2000 + off, oram[off], g.ram[off]);
            shown++;
        }
    }
    std::exit(1);
}

static void compare(const char *what)
{
    events++;
    if (loop_of(cpu->reg_PC) != g.cpu_loop) fail_report(what, "the two are in different loops");
    if ((cpu->INTE != 0) != (g.iff != 0)) fail_report(what, "interrupt enable differs");
    for (unsigned off = 0; off < 0x2000; off++)
        if (compared(off) && oram[off] != g.ram[off]) fail_report(what, "RAM differs");
    bytes_compared += 0x2000 - 0x100;
    if (o_shift_data != g.shift_data || o_shift_count != g.shift_count) fail_report(what, "shifter state differs");
    if (o_outs.size() != c_outs.size()) {
        std::printf("  port writes: ROM %zu, port %zu\n", o_outs.size(), c_outs.size());
        fail_report(what, "number of port writes differs");
    }
    for (size_t i = 0; i < o_outs.size(); i++) {
        // the watchdog's data byte is whatever is in A: only the write counts
        if (o_outs[i].port != c_outs[i].port || (o_outs[i].port != 4 && o_outs[i].val != c_outs[i].val)) {
            std::printf("  write %zu: ROM OUT %d,$%02X  port OUT %d,$%02X\n", i,
                        o_outs[i].port, o_outs[i].val, c_outs[i].port, c_outs[i].val);
            fail_report(what, "port writes differ");
        }
    }
    o_outs.clear();
    c_outs.clear();
}

// ---- what the ROM spends on each kind of event (--costs) ----------------------
struct Cost { unsigned long n; double sum, units; unsigned long long lo, hi; };
enum { C_WAIT_ATTRACT, C_WAIT_GAME, C_CMD /* + opcode / 2 */, C_IRQ_FLYER = C_CMD + 17, C_IRQ_IDLE, C_IRQ_EVEN, C_IRQ_ODD,
       C_SELFTEST, C_SWITCHTEST, C_COUNT };
static Cost costs[C_COUNT];
static bool want_costs;

static void cost_add(int cat, unsigned long long cyc, double units)
{
    Cost &c = costs[cat];
    if (c.n == 0 || cyc < c.lo) c.lo = cyc;
    if (cyc > c.hi) c.hi = cyc;
    c.n++;
    c.sum += (double)cyc;
    c.units += units;
}

static void cost_report()
{
    static const char *names[C_COUNT] = {
        "WAIT pass, attract", "WAIT pass, game",
        "cmd $00", "cmd $02 TEXT", "cmd $04 DELAY", "cmd $06 TIMEOUT", "cmd $08 GOTO", "cmd $0A SET", "cmd $0C CLEAR",
        "cmd $0E SCORE", "cmd $10 BIGTEXT", "cmd $12 IFZ", "cmd $14 IFNZ", "cmd $16 COINSTART", "cmd $18 ROW",
        "cmd $1A DECCOIN", "cmd $1C INCCOIN", "cmd $1E TONE", "cmd $20 QUIET",
        "interrupt: flyer update", "interrupt: flyer skipped", "interrupt: frame task, even", "interrupt: frame task, odd",
        "self-test pass", "switch-test pass" };
    std::printf("%-30s %9s %10s %9s %9s %12s\n", "8080 cycles per event", "events", "mean", "min", "max", "per unit");
    for (int i = 0; i < C_COUNT; i++) {
        const Cost &c = costs[i];
        if (!c.n) continue;
        std::printf("%-30s %9lu %10.0f %9llu %9llu", names[i], c.n, c.sum / c.n, c.lo, c.hi);
        if (c.units > 0) std::printf(" %12.1f", c.sum / c.units);
        std::printf("\n");
    }
}

// ---- events ---------------------------------------------------------------
static void event_pass()
{
    int    cat = C_SWITCHTEST;
    double units = 0;
    unsigned long long c0 = o_cycles;
    if (g.cpu_loop == LOOP_MAIN) {
        uint16_t sp = rd16(A_SCRIPT_PTR);
        uint8_t  op = cpu_rd(sp);
        if (op == 0) cat = GAME_ACTIVE ? C_WAIT_GAME : C_WAIT_ATTRACT;
        else {
            cat = C_CMD + (op >> 1);
            if (op == 0x02 || op == 0x10) units = cpu_rd((uint16_t)(sp + 1));          // characters
            if (op == 0x0C) units = cpu_rd((uint16_t)(sp + 1)) ? cpu_rd((uint16_t)(sp + 1)) : 256;   // 32-byte blocks
            if (cat >= C_IRQ_FLYER) cat = C_CMD;
        }
    } else if (g.cpu_loop == LOOP_SELF_TEST) cat = C_SELFTEST;
    oracle_run_to_sync();
    switch (g.cpu_loop) {
    case LOOP_MAIN:           main_loop_pass(); break;
    case LOOP_SELF_TEST:      self_test_pass(); break;
    case LOOP_SELF_TEST_WAIT: self_test_wait_pass(); break;
    default:                  switch_test_pass(); break;
    }
    ev_pass++;
    cost_add(cat, o_cycles - c0, units);
    compare("pass");
}

static void event_irq(int which)
{
    if (!g.iff) {                                         // both sides hold it (compare() checked INTE == iff)
        ev_held++;
        return;
    }
    unsigned long long c0 = o_cycles;
    uint8_t frame0 = FRAME_CTR;
    bool    could_update = FREEZE == 0 && CONTACT_ROW == 0 && (cpu_rd(rd16(A_FLYER_PTR)) & 0x80);
    cpu->interrupt(which == 1 ? 0x08 : 0x10);
    oracle_run_to_sync();
    g.iff = 0;
    if (which == 1) rst1(); else rst2();
    ev_irq++;
    if (FRAME_CTR != frame0) cost_add((FRAME_CTR & 1) ? C_IRQ_ODD : C_IRQ_EVEN, o_cycles - c0 + 11, 0);
    else cost_add(could_update ? C_IRQ_FLYER : C_IRQ_IDLE, o_cycles - c0 + 11, 0);
    compare(which == 1 ? "RST 1" : "RST 2");
}

static void run_period(int passes)
{
    if (g.cpu_loop == LOOP_MAIN) {
        int waits = 0, guard = 0;
        while (waits < passes && guard++ < 512) {
            event_pass();
            if (g.cpu_loop != LOOP_MAIN) break;
            if (g.iff) waits++;
        }
    } else {
        event_pass();
    }
}

// ---- scripted inputs --------------------------------------------------------
#define MAX_EVENTS 32
struct Press { long frame; int what; };
static Press presses[MAX_EVENTS];
static int   npresses;
static bool  track, test_on;
static long  test_off_frame = -1;
static int   fixed_paddle = 0x7F;
static uint8_t dip_low;
struct Window { long from, to; };
static Window windows[MAX_EVENTS];        // --track-frames: steer only inside these
static int    nwindows;

static void set_inputs(long f, const uint8_t *ram)
{
    in_switch = 0xFF;
    for (int i = 0; i < npresses; i++) {
        if (f >= presses[i].frame && f < presses[i].frame + 6) {
            if (presses[i].what == 0) in_switch &= (uint8_t)~0x40;
            if (presses[i].what == 1) in_switch &= (uint8_t)~0x20;
            if (presses[i].what == 2) in_switch &= (uint8_t)~0x10;
        }
    }
    bool t = test_on && !(test_off_frame >= 0 && f >= test_off_frame);
    in_dip = (uint8_t)((dip_low & 0x7F) | (t ? 0x80 : 0x00));
    in_paddle[0] = in_paddle[1] = (uint8_t)fixed_paddle;
    bool tracking = track;
    for (int i = 0; i < nwindows; i++)
        if (f >= windows[i].from && f < windows[i].to) tracking = true;
    if (tracking) {
        // what Autopilot ($0CE5) computes, fed in as the paddle
        uint16_t fl = (uint16_t)(ram[A_FLYER_PTR - 0x2000] | (ram[A_FLYER_PTR + 1 - 0x2000] << 8));
        if (fl >= 0x2000 && fl < 0x4000 && (ram[fl - 0x2000] & 0x80)) {
            uint8_t x = ram[fl + K_CL_X - 0x2000];
            uint8_t a = (uint8_t)(((ram[A_SEESAW_STATE - 0x2000] & 0x20) ? 0xFC : 0xE8) + x);
            if (a >= 0xE0) a = (uint8_t)(((uint8_t)(x + 1) & 0x80) ? 0xD7 : 0x00);
            in_paddle[0] = in_paddle[1] = a;
        }
    }
}

// ---- the oracle alone, with cycle-timed interrupts ---------------------------
struct Shot { long frame; const char *file; };

static int free_run(long frames, Shot *shots, int nshots)
{
    const long LINE = 128, FRAME = 262 * LINE;            // CPU cycles
    const long T_RST1 = 134 * LINE;                       // line 96, counted from line 224
    unsigned long passes_attract = 0, passes_game = 0, frames_attract = 0, frames_game = 0;
    unsigned long taken = 0, late = 0, lost = 0;
    bool pending = false;
    unsigned long long raised_at = 0;

    oracle_power_on();
    for (long f = 0; f < frames; f++) {
        set_inputs(f, oram);
        unsigned long long start = o_cycles;
        unsigned long passes = 0;
        bool raised1 = false;
        if (pending) lost++;
        pending = true;                                   // line 224: the vblank interrupt is raised
        raised_at = o_cycles;
        while ((long)(o_cycles - start) < FRAME) {
            long t = (long)(o_cycles - start);
            if (!raised1 && t >= T_RST1) {                // line 96
                raised1 = true;
                if (pending) lost++;
                pending = true;
                raised_at = o_cycles;
            }
            if (pending && cpu->INTE) {
                // the vector follows the beam at the moment it is taken (MAME: counter bit 6)
                long vline = (224 + t / LINE) % 262;
                unsigned counter = vline < 224 ? (unsigned)(vline + 0x20) : (unsigned)(0xDA + (vline - 224));
                bool rst2 = (counter & 0x40) != 0;
                if (o_cycles - raised_at > 2 * (unsigned long long)LINE) late++;   // held by a DI for 2+ lines
                cpu->interrupt(rst2 ? 0x10 : 0x08);
                o_cycles += 11;
                pending = false;
                taken++;
            }
            oracle_step();
            if (cpu->reg_PC == R_MainLoop) passes++;
        }
        if (oram[A_GAME_ACTIVE - 0x2000]) { passes_game += passes; frames_game++; }
        else { passes_attract += passes; frames_attract++; }
        for (int i = 0; i < nshots; i++)
            if (shots[i].frame == f) shot_write_png(shots[i].file, &oram[0x400], 2);
    }
    std::printf("free run: %ld frames, %lu instructions, %lu interrupts taken (%lu held 2+ lines by a DI, %lu lost)\n",
                frames, o_instr, taken, late, lost);
    if (frames_attract)
        std::printf("  attract: %.2f main-loop passes per frame (%.2f per interrupt period) over %lu frames\n",
                    (double)passes_attract / frames_attract, (double)passes_attract / frames_attract / 2, frames_attract);
    if (frames_game)
        std::printf("  game:    %.2f main-loop passes per frame (%.2f per interrupt period) over %lu frames\n",
                    (double)passes_game / frames_game, (double)passes_game / frames_game / 2, frames_game);
    std::printf("  P1 %02X%02X0  P2 %02X%02X0  high %02X%02X0  script $%04X\n",
                oram[A_P1_SCORE - 0x2000], oram[A_P1_SCORE + 1 - 0x2000],
                oram[A_P2_SCORE - 0x2000], oram[A_P2_SCORE + 1 - 0x2000],
                oram[A_HI_SCORE - 0x2000], oram[A_HI_SCORE + 1 - 0x2000],
                oram[A_SCRIPT_PTR - 0x2000] | (oram[A_SCRIPT_PTR + 1 - 0x2000] << 8));
    return 0;
}

int main(int argc, char **argv)
{
    long frames = 600;
    int  passes = 4, nshots = 0;
    bool free_mode = false;
    Shot shots[MAX_EVENTS];

    for (int i = 1; i < argc; i++) {
        if (!std::strcmp(argv[i], "--frames") && i + 1 < argc) frames = std::atol(argv[++i]);
        else if (!std::strcmp(argv[i], "--coin") && i + 1 < argc && npresses < MAX_EVENTS) presses[npresses++] = { std::atol(argv[++i]), 0 };
        else if (!std::strcmp(argv[i], "--start1") && i + 1 < argc && npresses < MAX_EVENTS) presses[npresses++] = { std::atol(argv[++i]), 1 };
        else if (!std::strcmp(argv[i], "--start2") && i + 1 < argc && npresses < MAX_EVENTS) presses[npresses++] = { std::atol(argv[++i]), 2 };
        else if (!std::strcmp(argv[i], "--paddle") && i + 1 < argc) fixed_paddle = std::atoi(argv[++i]) & 0xFF;
        else if (!std::strcmp(argv[i], "--track")) track = true;
        else if (!std::strcmp(argv[i], "--track-frames") && i + 2 < argc && nwindows < MAX_EVENTS) {
            windows[nwindows].from = std::atol(argv[++i]);
            windows[nwindows++].to = std::atol(argv[++i]);
        }
        else if (!std::strcmp(argv[i], "--dip") && i + 1 < argc) dip_low = (uint8_t)std::strtol(argv[++i], nullptr, 0);
        else if (!std::strcmp(argv[i], "--test")) test_on = true;
        else if (!std::strcmp(argv[i], "--testoff") && i + 1 < argc) test_off_frame = std::atol(argv[++i]);
        else if (!std::strcmp(argv[i], "--passes") && i + 1 < argc) passes = std::atoi(argv[++i]);
        else if (!std::strcmp(argv[i], "--quiet")) quiet = true;
        else if (!std::strcmp(argv[i], "--costs")) want_costs = true;
        else if (!std::strcmp(argv[i], "--coverage") && i + 1 < argc) coverage_file = argv[++i];
        else if (!std::strcmp(argv[i], "--trace")) trace = true;
        else if (!std::strcmp(argv[i], "--trace-every") && i + 1 < argc) { trace = true; trace_every = std::atol(argv[++i]); if (trace_every < 1) trace_every = 1; }
        else if (!std::strcmp(argv[i], "--free")) free_mode = true;
        else if (!std::strcmp(argv[i], "--shot") && i + 2 < argc && nshots < MAX_EVENTS) {
            shots[nshots].frame = std::atol(argv[++i]);
            shots[nshots++].file = argv[++i];
        }
        else { std::fprintf(stderr, "unknown option %s\n", argv[i]); return 2; }
    }
    if (passes < 1) passes = 1;

    if (free_mode) return free_run(frames, shots, nshots);

    // power on both
    set_inputs(0, g.ram);
    oracle_power_on();
    oracle_run_to_sync();
    std::memset(&g, 0, sizeof g);
    reset();
    compare("power-on");

    for (cur_frame = 0; cur_frame < frames; cur_frame++) {
        set_inputs(cur_frame, g.ram);
        if (trace && cur_frame % trace_every == 0) {
            uint16_t fl = rd16(A_FLYER_PTR);
            std::printf("frame %5ld  script $%04X  game %d  player %02X  jumps %d  P1 %02X%02X0  P2 %02X%02X0"
                        "  hold %02X  tmr script %02X splat %02X/%d  evt %02X  flyer $%04X st %02X fr %02X x %02X y %02X"
                        "  again %02X two %02X next %02X/%d\n",
                        cur_frame, rd16(A_SCRIPT_PTR), GAME_ACTIVE, PLAYER, JUMPS_LEFT,
                        g.ram[A_P1_SCORE - 0x2000], g.ram[A_P1_SCORE + 1 - 0x2000],
                        g.ram[A_P2_SCORE - 0x2000], g.ram[A_P2_SCORE + 1 - 0x2000],
                        SCRIPT_HOLD, TMR_SCRIPT, TMR_SPLAT, SPLAT_CTR, EVT_TIMERS, fl,
                        cpu_rd(fl), cpu_rd((uint16_t)(fl + 1)), cpu_rd((uint16_t)(fl + 3)), cpu_rd((uint16_t)(fl + 5)),
                        JUMPS_AGAIN, TWO_PLAYERS, NEXT_PLAYER, NEXT_JUMPS_LEFT);
        }
        event_irq(2);
        run_period(passes);
        event_irq(1);
        run_period(passes);
        for (int i = 0; i < nshots; i++)                  // the port's picture (equal to the ROM's)
            if (shots[i].frame == cur_frame) shot_write_png(shots[i].file, &g.ram[0x400], 2);
    }

    if (!quiet) {
        std::printf("frames %ld  events %lu (%lu passes, %lu interrupts, %lu held)  oracle instructions %lu\n",
                    frames, events, ev_pass, ev_irq, ev_held, o_instr);
        std::printf("RAM bytes compared %llu  script $%04X  game %d  P1 %02X%02X0  P2 %02X%02X0  high %02X%02X0\n",
                    bytes_compared, rd16(A_SCRIPT_PTR), GAME_ACTIVE,
                    g.ram[A_P1_SCORE - 0x2000], g.ram[A_P1_SCORE + 1 - 0x2000],
                    g.ram[A_P2_SCORE - 0x2000], g.ram[A_P2_SCORE + 1 - 0x2000],
                    g.ram[A_HI_SCORE - 0x2000], g.ram[A_HI_SCORE + 1 - 0x2000]);
        std::printf("stray writes: ROM %lu, port %u\n", o_stray, (unsigned)g.stray_writes);
    }
    if (o_stray != g.stray_writes) {
        std::printf("LOCKSTEP: FAIL - writes into ROM space differ (ROM %lu, port %u)\n", o_stray, (unsigned)g.stray_writes);
        return 1;
    }
    if (want_costs) cost_report();
    if (coverage_file) {                                  // accumulate over runs: OR into the file
        uint8_t old[PROGROM_SIZE];
        std::FILE *fp = std::fopen(coverage_file, "rb");
        if (fp) {
            if (std::fread(old, 1, sizeof old, fp) == sizeof old)
                for (unsigned i = 0; i < PROGROM_SIZE; i++) coverage[i] |= old[i];
            std::fclose(fp);
        }
        fp = std::fopen(coverage_file, "wb");
        if (!fp || std::fwrite(coverage, 1, sizeof coverage, fp) != sizeof coverage) {
            std::fprintf(stderr, "cannot write %s\n", coverage_file);
            return 1;
        }
        std::fclose(fp);
    }
    std::printf("LOCKSTEP: PASS\n");
    return 0;
}
