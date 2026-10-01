/* state.h - Clowns C port: the whole machine state.
 *
 * Same state model as the Tempest port: the machine's own memory, raw, so that
 * all of it can be byte-compared with the real ROM running on an 8080
 * (tests/).  Named cells go through the generated aliases in state_defs.h
 * (tools/gen_state.py from ../disasm/clowns_defines.asm); ROM tables are read
 * at their ROM addresses from the generated image (progrom.c, rom_labels.h).
 */
#ifndef STATE_H
#define STATE_H

#include <stdint.h>

typedef struct {
    uint8_t  ram[0x2000];     /* $2000-$3FFF: work RAM $2000-$23FF, video RAM $2400-$3FFF */

    /* ---- MB14241 shifter (ports 1-3) ------------------------------------- */
    uint16_t shift_data;      /* 15 bits: the last byte written in b7-b14, the
                                 top 7 bits of the one before in b0-b6          */
    uint8_t  shift_count;     /* ~(value written to port 1) & 7                 */

    /* ---- CPU facts that RAM cannot hold ----------------------------------- */
    uint8_t  iff;             /* interrupt enable flip-flop: EI = 1, DI = 0     */
    uint8_t  cpu_loop;        /* which endless loop the CPU is in (LOOP_*)      */

    /* ---- seam bookkeeping (not machine state) ----------------------------- */
    uint32_t pass_count;      /* main-loop passes since reset                   */
    uint32_t irq_count;       /* interrupts serviced since reset                */
    uint32_t stray_writes;    /* cpu_wr() into ROM space (ignored, as on the board) */
    uint16_t stray_addr;      /* the last such address                          */
} machine_state;

/* The CPU is always in one of these loops; the seam runs one pass at a time
 * and delivers interrupts between passes when g.iff is set. */
#define LOOP_MAIN           0   /* MainLoop ($0A51): main_loop_pass()             */
#define LOOP_SELF_TEST      1   /* RamTest + RomTest ($0022): self_test_pass()    */
#define LOOP_SELF_TEST_WAIT 2   /* SelfTestWait ($011F): self_test_wait_pass()    */
#define LOOP_SWITCH_TEST    3   /* SwitchTest ($134D): switch_test_pass()         */

extern machine_state g;

#include "state_defs.h"
#include "rom_labels.h"
#include "progrom.h"

/* RAM at a CPU address known to be in $2000-$3FFF. */
#define MEM(a)   (g.ram[(a) & 0x1FFF])
/* ROM at a CPU address $0000-$17FF. */
#define ROM(a)   (progrom[(a)])

/* An 8080 read / write at a computed address, through the board's address
 * decoding (state.c): ROM space reads the ROM image (0 where no ROM is fitted)
 * and ignores writes. */
uint8_t  cpu_rd(uint16_t addr);
void     cpu_wr(uint16_t addr, uint8_t v);

/* 16-bit cells (low byte first): the script pointer, the clown pointers ... */
static inline uint16_t rd16(uint16_t addr)
{
    return (uint16_t)(cpu_rd(addr) | ((uint16_t)cpu_rd((uint16_t)(addr + 1)) << 8));
}
static inline void wr16(uint16_t addr, uint16_t v)
{
    cpu_wr(addr, (uint8_t)v);
    cpu_wr((uint16_t)(addr + 1), (uint8_t)(v >> 8));
}

/* ---- MB14241 shifter: OUT 1, OUT 2, IN 3 --------------------------------
 * Part of the machine, not of the seam: its answers depend only on what the
 * game wrote.  Semantics as MAME's mb14241_device. */
static inline void    shift_amt(uint8_t v)  { g.shift_count = (uint8_t)(~v & 0x07); }
static inline void    shift_data(uint8_t v) { g.shift_data = (uint16_t)((g.shift_data >> 8) | ((uint16_t)v << 7)); }
static inline uint8_t shift_in(void)        { return (uint8_t)(g.shift_data >> g.shift_count); }

/* ---- 8080 flag helpers ---------------------------------------------------- */
/* P flag of a result: 1 = even parity (JPE taken), 0 = odd (JPO taken). */
static inline int parity_even(uint8_t v)
{
    v ^= (uint8_t)(v >> 4);
    v ^= (uint8_t)(v >> 2);
    v ^= (uint8_t)(v >> 1);
    return !(v & 1);
}

/* ADD / ADC followed by DAA, as the 8080 does it: returns the adjusted sum,
 * *cy is the carry in (ADC) and out. */
static inline uint8_t add_daa(uint8_t a, uint8_t v, unsigned *cy)
{
    unsigned cin = *cy ? 1u : 0u;
    unsigned sum = (unsigned)a + v + cin;
    unsigned ac = ((a & 0x0Fu) + (v & 0x0Fu) + cin) > 0x0Fu;
    unsigned c = sum > 0xFFu;
    uint8_t  r = (uint8_t)sum;
    uint8_t  lsb = (uint8_t)(r & 0x0F), msb = (uint8_t)(r >> 4);
    uint8_t  fix = 0;
    if (ac || lsb > 9) fix = 0x06;
    if (c || msb > 9 || (msb >= 9 && lsb > 9)) { fix = (uint8_t)(fix + 0x60); c = 1; }
    *cy = c;
    return (uint8_t)(r + fix);
}

#endif /* STATE_H */
