/* script.c - SECTION 8 ($1413-$1525): the script command handlers.
 *
 * MainLoop dispatches through the ROM's own ScriptOps table: the handler
 * address is read from the ROM image and matched against the listing's labels,
 * so the table is never retyped.  Each handler gets DE -> its arguments and
 * stores the new SCRIPT_PTR.
 */
#include "state.h"
#include "hw.h"
#include "game.h"

/* ScriptWord ($1504): DE = word at HL; SCRIPT_PTR -> after it. */
static uint16_t script_word(uint16_t hl)
{
    uint16_t de = rd16(hl);                                /* L1504-L1506 */
    wr16(A_SCRIPT_PTR, (uint16_t)(hl + 2));                /* L1507-L1508 */
    return de;
}

/* ScriptByteWord ($1501): A = byte at DE, DE = word after it; SCRIPT_PTR -> after both. */
static uint8_t script_byte_word(uint16_t *de)
{
    uint8_t a = cpu_rd(*de);                               /* L1501-L1502 */
    *de = script_word((uint16_t)(*de + 1));                /* L1503, falls into ScriptWord */
    return a;
}

/* OpClear ($1433): CLEAR n. */
static void op_clear(uint16_t de)
{
    uint8_t a = cpu_rd(de);                                /* L1433-L1434 */
    wr16(A_SCRIPT_PTR, (uint16_t)(de + 1));                /* L1435-L1436 */
    clear_ram_top(a);                                      /* L1439 JMP ClearRamTop -> MainLoop */
}

/* OpText ($1442) / OpBigText ($143C), OpTextCommon ($1445): TEXT / BIGTEXT n, text, screen. */
static void op_text_common(uint16_t de, int big)
{
    uint8_t  a = cpu_rd(de);                               /* L1446-L1447 */
    uint16_t text = rd16((uint16_t)(de + 1));              /* L1448-L144D */
    uint16_t scr = script_word((uint16_t)(de + 3));        /* L144C, L144E */
    if (big) draw_big_string(a, &text, &scr);              /* L1451-L1452: RET into the draw routine */
    else     draw_string(a, &text, &scr);
}

/* OpDelay ($1453): DELAY n. */
static void op_delay(uint16_t de)
{
    SCRIPT_HOLD = 0;                                       /* L1453-L1454 */
    TMR_SCRIPT = cpu_rd(de);                               /* L1457-L1459 */
    wr16(A_SCRIPT_PTR, (uint16_t)(de + 1));                /* L145C-L145D */
}

/* OpTimeout ($1461): TIMEOUT n, addr. */
static void op_timeout(uint16_t de)
{
    TIMEOUT_HOLD = 0;                                      /* L1461-L1462 */
    TMR_TIMEOUT = cpu_rd(de);                              /* L1465-L1467 */
    wr16(A_TIMEOUT_PTR, script_word((uint16_t)(de + 1)));  /* L146A-L146F */
}

/* OpGoto ($1473): GOTO addr. */
static void op_goto(uint16_t de)
{
    wr16(A_SCRIPT_PTR, rd16(de));                          /* L1473-L1478 */
}

/* OpSet ($147C): SET value, addr. */
static void op_set(uint16_t de)
{
    uint8_t a = script_byte_word(&de);                     /* L147C */
    cpu_wr(de, a);                                         /* L147F */
}

/* OpScore ($1481): SCORE score, screen. */
static void op_score(uint16_t de)
{
    uint16_t bc = rd16(de);                                /* L1481-L1484 */
    uint16_t hl = A_TEXT_BUF;                              /* L1487 */
    uint16_t scr;
    format_score(&bc, &hl);                                /* L148A */
    scr = script_word((uint16_t)(de + 2));                 /* L1485, L148D-L148E */
    hl = A_TEXT_BUF;                                       /* L1491 */
    draw_string(0x05, &hl, &scr);                          /* L1494-L1496 */
}

/* OpTestArgs ($14AF): A = byte at the first argument; *target = second argument;
 * returns HL -> the next command. */
static uint16_t op_test_args(uint16_t de, uint8_t *a, uint16_t *target)
{
    *a = cpu_rd(rd16(de));                                 /* L14AF-L14B4 */
    *target = rd16((uint16_t)(de + 2));                    /* L14B5-L14B7 */
    return (uint16_t)(de + 4);                             /* L14B8 */
}

/* OpIfZ ($1499): IFZ addr, target. */
static void op_ifz(uint16_t de)
{
    uint8_t  a;
    uint16_t target, next = op_test_args(de, &a, &target); /* L1499 */
    wr16(A_SCRIPT_PTR, a != 0 ? next : target);            /* L149C-L14A0 */
}

/* OpIfNZ ($14A4): IFNZ addr, target. */
static void op_ifnz(uint16_t de)
{
    uint8_t  a;
    uint16_t target, next = op_test_args(de, &a, &target); /* L14A4 */
    wr16(A_SCRIPT_PTR, a == 0 ? next : target);            /* L14A7-L14AB */
}

/* OpCoinStart ($14BB): COINSTART. */
static void op_coin_start(void)
{
    uint8_t a = COINS, d;                                  /* L14BB-L14BE */
    if (a == 0) return;                                    /* L14BF-L14C0 */
    COINS = (uint8_t)(COINS - 1);                          /* L14C1 */
    SCRIPT_HOLD = a;                                       /* L14C2 */
    TIMEOUT_HOLD = a;                                      /* L14C5 */
    d = hw_in_dip();                                       /* L14C8-L14CA */
    NEXT_JUMPS_LEFT = (uint8_t)((d & 0x40) ? 0x04 : 0x03); /* L14CB-L14D3 */
    wr16(A_SCRIPT_PTR, rd16((uint16_t)(R_CoinageScripts + 2 * (d & 0x03))));   /* L14D6-L14E5 */
}

/* FillBalloonRow ($14EE): 12 balloons at height B, 21 pixels apart from X = 0. */
uint16_t fill_balloon_row(uint16_t hl, uint8_t b)
{
    uint8_t d = 0x0C, e = 0x00;                            /* L14EE */
    do {
        cpu_wr(hl, 0x80); hl++;                            /* L14F1-L14F3 */
        cpu_wr(hl, e); hl++;                               /* L14F4, L14F9 */
        e = (uint8_t)(e + 0x15);                           /* L14F5-L14F8 */
        cpu_wr(hl, b); hl++;                               /* L14FA-L14FB */
    } while (--d != 0);                                    /* L14FC-L14FD */
    return hl;
}

/* OpRow ($14E9): ROW y, addr. */
static void op_row(uint16_t de)
{
    uint8_t b = script_byte_word(&de);                     /* L14E9-L14EC */
    fill_balloon_row(de, b);                               /* L14ED, falls into FillBalloonRow */
}

/* MainLoop's dispatch ($0A64-$0A70) through ScriptOps ($1413). */
void script_command(uint8_t op, uint16_t de)
{
    uint16_t handler = rd16((uint16_t)(R_ScriptOps - 2 + op));   /* L0A65-L0A6F */
    switch (handler) {                                     /* L0A70 PCHL */
    case R_OpText:      op_text_common(de, 0); break;      /* $02 */
    case R_OpDelay:     op_delay(de); break;               /* $04 */
    case R_OpTimeout:   op_timeout(de); break;             /* $06 */
    case R_OpGoto:      op_goto(de); break;                /* $08 */
    case R_OpSet:       op_set(de); break;                 /* $0A */
    case R_OpClear:     op_clear(de); break;               /* $0C */
    case R_OpScore:     op_score(de); break;               /* $0E */
    case R_OpBigText:   op_text_common(de, 1); break;      /* $10 */
    case R_OpIfZ:       op_ifz(de); break;                 /* $12 */
    case R_OpIfNZ:      op_ifnz(de); break;                /* $14 */
    case R_OpCoinStart: op_coin_start(); break;            /* $16 */
    case R_OpRow:       op_row(de); break;                 /* $18 */
    case R_OpDecCoin:   COINS = (uint8_t)(COINS - 1); break;   /* $1A  L150C-L150F */
    case R_OpIncCoin:   COINS = (uint8_t)(COINS + 1); break;   /* $1C  L1511-L1514 */
    case R_OpTone:                                         /* $1E  OpTone ($1516) */
        hw_tone_lo(0x3F);                                  /* L1516-L1518 */
        hw_tone_hi(0x1A);                                  /* L151A-L151C */
        break;
    case R_OpQuiet:                                        /* $20  OpQuiet ($151F) */
        hw_tone_lo(0);                                     /* L151F-L1520 */
        hw_sound(0);                                       /* L1522 */
        break;
    default:
        break;                                             /* not a script opcode: the ROM would run wild */
    }
}
