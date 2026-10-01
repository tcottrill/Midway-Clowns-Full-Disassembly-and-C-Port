/* switchtest.c - SECTION 7 ($1349-$1412): the switch test and the RAM clear. */
#include "state.h"
#include "hw.h"
#include "game.h"

/* DrawPlayerWord ($13B3): "PLAYER" at DE and a blank column; the ROM returns A = 1. */
static void draw_player_word(uint16_t *hl, uint16_t *de)
{
    *hl = R_TxtPlayer;                                     /* L13B3 */
    draw_string(0x06, hl, de);                             /* L13B6-L13B8 */
    (*de)++;                                               /* L13BB */
}                                                          /* L13BC INR A: A = 1 */

/* DrawOnOff ($13C5): one blank column, then "ON " if Z was set, else "OFF". */
static void draw_on_off(int z, uint16_t *de)
{
    uint16_t hl = R_TxtOn;                                 /* L13C6 */
    (*de)++;                                               /* L13C5 */
    if (!z) hl = R_TxtOff;                                 /* L13C9-L13CC */
    draw_string(0x03, &hl, de);                            /* L13CF-L13D1 */
}

/* SwitchTest ($1349): entered from the RAM test when the coin switch is held. */
void switch_test(void)
{
    clear_ram_top(0);                                      /* L1349-L134A: all RAM */
    g.cpu_loop = LOOP_SWITCH_TEST;
}

/* SwitchTest's loop ($134D-$13B0): one trip. */
void switch_test_pass(void)
{
    uint16_t hl, de;
    uint8_t  a;
    int      z;

    g.iff = 1;                                             /* L134D EI */
    hw_watchdog();                                         /* L134E */
    draw_playfield();                                      /* L1350 */
    SEESAW_STATE = 0x80;                                   /* L1353-L1355 */
    hl = R_TxtCoin;                                        /* L1358 */
    de = 0x3000;                                           /* L135B */
    PADDLE_ENABLE = 0x04;                                  /* L135E-L1360 */
    draw_string(0x04, &hl, &de);                           /* L1363: HL moves on to "OFF" */
    de++;                                                  /* L1366 */
    a = (uint8_t)(hw_in_switch() & 0x40);                  /* L1367-L1369 */
    if (a == 0) {                                          /* L136B */
        hl = R_TxtOn;                                      /* L136E */
        a = 0x01;                                          /* L1371: coin counter on */
    }
    OUT3_SHADOW = a;                                       /* L1373 */
    draw_string(0x03, &hl, &de);                           /* L1376-L1378 */
    de = 0x3400;                                           /* L137B */
    draw_player_word(&hl, &de);                            /* L137E */
    draw_string(0x01, &hl, &de);                           /* L1381 DrawCharReadSwitches ($13BF): "1" */
    a = hw_in_switch();                                    /* L13C2 */
    z = (a & 0x20) == 0;                                   /* L1384 */
    if (z) PLAYER = 0x00;                                  /* L1386-L138B */
    draw_on_off(z, &de);                                   /* L138E */
    de = 0x3800;                                           /* L1391 */
    draw_player_word(&hl, &de);                            /* L1394 */
    hl++;                                                  /* L1397 DrawNextChar ($13BE): skip the "1" */
    draw_string(0x01, &hl, &de);                           /* L13BF: "2" */
    a = hw_in_switch();                                    /* L13C2 */
    z = (a & 0x10) == 0;                                   /* L139A */
    if (z) PLAYER = 0xFF;                                  /* L139C-L13A1 */
    draw_on_off(z, &de);                                   /* L13A4 */
    /* L13A7-L13AD: a 1024-count delay loop; L13B0 JMP back to $134D */
}

/* ClearRamTop ($13E7): zero A x 32 bytes downward from $4000 (A = 0: all of
 * RAM).  The ROM does it with pushes and jumps to the popped return address;
 * here it simply returns. */
void clear_ram_top(uint8_t a)
{
    uint16_t sp = 0x4000;                                  /* L13EC */
    int      i;

    g.iff = 0;                                             /* L13E7 DI */
    do {
        for (i = 0; i < 32; i++) {                         /* L13EF-L13FE: 16 x PUSH B */
            sp--;
            MEM(sp) = 0;
        }
    } while (--a != 0);                                    /* L13FF-L1400 */
    /* L1403 LXI SP,$2400 */
    PLAYER = NEXT_PLAYER;                                  /* L1406-L1409 */
    JUMPS_LEFT = NEXT_JUMPS_LEFT;                          /* L140C-L140F */
}                                                          /* L1412 PCHL */
