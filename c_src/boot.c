/* boot.c - SECTION 1 ($0000-$0137): reset, the self test (RAM and ROM).
 *
 * The self test never uses RAM for its own state: on the 8080 everything is
 * in registers, here in locals.  It runs with interrupts off.  One call of
 * self_test_pass() is one complete RAM + ROM test, after which the ROM either
 * starts again through Reset (all good), waits in SelfTestWait (something was
 * reported) or has left for the switch test (coin switch held).
 */
#include "state.h"
#include "hw.h"
#include "game.h"

static void ram_error(uint8_t d, uint8_t e);
static void rom_test(void);

/* Reset ($0000) and Boot ($0018): choose between the self test and the game. */
void reset(void)
{
    g.iff = 0;                                             /* a CPU reset disables interrupts */
    /* L0002 LXI SP,$2400 / L0005 JMP Boot */
    if (hw_in_dip() & 0x80) {                              /* L0018-L001C JNZ RamTest */
        g.cpu_loop = LOOP_SELF_TEST;
        return;
    }
    game_start();                                          /* L001F JMP GameStart */
}

/* RamTest ($0022): walking-bit test of all RAM $2000-$3FFF. */
void self_test_pass(void)
{
    uint8_t  b = 0x01;                                     /* L0022 */
    uint8_t  d = 0, e = 0;                                 /* L0024: bad bits, even / odd addresses */
    uint16_t hl;
    uint8_t  a;
    unsigned cy;

    do {
        hl = A_WorkRam;                                    /* L0027 */
        /* Pass 1, upward: write the pattern and read it straight back */
        do {
            hw_watchdog();                                 /* L002A */
            if (!(hw_in_switch() & 0x40)) { switch_test(); return; }   /* L002C-L0030 */
            MEM(hl) = b;                                   /* L0033 */
            a = (uint8_t)(MEM(hl) ^ b);                    /* L0034-L0035 */
            if (a != 0) {                                  /* L0036 */
                if (hl & 1) e |= a; else d |= a;           /* L0039-L0047 */
            }
            hl++;                                          /* L0048 */
        } while ((hl >> 8) != 0x40);                       /* L0049-L004C */
        /* Pass 2, downward: check the pattern, replace it with its complement */
        for (;;) {
            hw_watchdog();                                 /* L004F */
            if (!(hw_in_switch() & 0x40)) { switch_test(); return; }   /* L0051-L0055 */
            hl--;                                          /* L0058 */
            if ((hl >> 8) == 0x1F) break;                  /* L0059-L005C */
            a = (uint8_t)(MEM(hl) ^ b);                    /* L005F-L0060 */
            if (a != 0) {                                  /* L0061 */
                if (hl & 1) e |= a; else d |= a;           /* L0064-L0072 */
            }
            MEM(hl) = (uint8_t)~b;                         /* L0073-L0075 */
            a = (uint8_t)((uint8_t)~b ^ MEM(hl));          /* L0076 */
            if (a != 0) {                                  /* L0077 */
                if (hl & 1) e |= a; else d |= a;           /* L007A-L0088 */
            }
        }                                                  /* L0089 */
        /* Pass 3, upward: check the complement, leave RAM cleared */
        for (;;) {
            hw_watchdog();                                 /* L008C */
            if (!(hw_in_switch() & 0x40)) { switch_test(); return; }   /* L008E-L0092 */
            hl++;                                          /* L0095 */
            if ((hl >> 8) == 0x40) break;                  /* L0096-L0099 */
            a = (uint8_t)((uint8_t)~b ^ MEM(hl));          /* L009C-L009E */
            if (a != 0) {                                  /* L009F */
                if (hl & 1) e |= a; else d |= a;           /* L00A2-L00B0 */
            }
            MEM(hl) = 0;                                   /* L00B1-L00B2 */
        }                                                  /* L00B3 */
        cy = b >> 7;                                       /* L00B6-L00B8 RLC */
        b = (uint8_t)((b << 1) | cy);
    } while (!cy);                                         /* L00B9 */

    if ((d | e) != 0) {                                    /* L00BC-L00BE */
        ram_error(d, e);
        return;
    }
    rom_test();
}

/* RamError ($00C1): show the bad RAM bits as 16 columns over the whole screen. */
static void ram_error(uint8_t d, uint8_t e)
{
    uint16_t sp = (uint16_t)((d << 8) | e);                /* L00C1-L00C2 */
    uint16_t de = A_WorkRam;                               /* L00C3 */
    uint8_t  b = 0;                                        /* L00C6: 256 groups */
    do {
        uint16_t hl = sp;                                  /* L00C8-L00CB */
        uint8_t  c = 0x10;                                 /* L00CC */
        do {
            uint8_t  a = 0;                                /* L00CE */
            unsigned cy = hl >> 15;                        /* L00CF DAD H */
            hl = (uint16_t)(hl << 1);
            if (!cy) a = 0xFF;                             /* L00D0-L00D3 */
            MEM(de) = a; de++;                             /* L00D4-L00D5 */
            MEM(de) = 0x18; de++;                          /* L00D6-L00D9 */
        } while (--c != 0);                                /* L00DA-L00DB */
    } while (--b != 0);                                    /* L00DE-L00DF */
    g.cpu_loop = LOOP_SELF_TEST_WAIT;                      /* L00E2 JMP SelfTestWait */
}

/* RomTest ($00E5): checksum the six ROMs, print the letter of each bad one. */
static void rom_test(void)
{
    uint16_t screen = 0x360C;                              /* L00E8-L00EB (kept on the stack) */
    uint16_t hl = 0x0000;                                  /* L00EC */
    uint16_t de = R_RomCheckTable;                         /* L00EF */

    do {
        uint8_t  a = ROM(de);                              /* L00F5 */
        unsigned n;
        de++;                                              /* L00F6 */
        for (n = 0x400; n != 0; n--) {                     /* L00F2: B = 4, C = 0 */
            a = (uint8_t)(a + cpu_rd(hl));                 /* L00F7 */
            hw_watchdog();                                 /* L00F8 */
            hl++;                                          /* L00FA */
        }                                                  /* L00FB-L0100 */
        a++;                                               /* L0103 */
        if (a != 0) {                                      /* L0104 */
            draw_string(1, &de, &screen);                  /* L0107-L010F: the ROM's letter; both pointers step */
            /* L0110 DCX D cancels L0111 INX D */
        } else {
            de++;                                          /* L0111: skip the letter */
        }
    } while ((hl >> 8) != 0x18);                           /* L0112-L0115 */

    if ((screen & 0xFF) == 0x0C) {                         /* L0118-L011C JZ Reset */
        reset();
        return;
    }
    g.cpu_loop = LOOP_SELF_TEST_WAIT;                      /* falls into SelfTestWait */
}

/* SelfTestWait ($011F): hold the error display until the self-test switch goes off. */
void self_test_wait_pass(void)
{
    hw_watchdog();                                         /* L011F */
    if (!(hw_in_dip() & 0x80)) reset();                    /* L0121-L0125 JZ Reset */
}                                                          /* L0128 JMP SelfTestWait */
