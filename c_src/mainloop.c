/* mainloop.c - SECTION 4 ($0A41-$0DF3): game start, the main loop and its
 * tasks: balloons, serve, score line, playfield, autopilot, row bonus.
 *
 * The ROM's MainLoop pushes its own address and never ends; here one call of
 * main_loop_pass() is one trip round it.  A pass either runs ONE script
 * command (interrupts off) or, with the script on a WAIT, the game tasks
 * (interrupts on).  The seam (app_loop.c) calls it for ever and runs the
 * interrupts between passes while g.iff is set.
 */
#include "state.h"
#include "hw.h"
#include "game.h"

static void award_row_bonus(uint8_t a, uint16_t hl);

/* GameStart ($0A41): normal power-on: clear all RAM, script at AttractScript. */
void game_start(void)
{
    hw_tone_lo(0);                                         /* L0A41-L0A42 */
    hw_tone_hi(0);                                         /* L0A44 */
    hw_sound(0);                                           /* L0A46 */
    clear_ram_top(0);                                      /* L0A48: all 256 blocks */
    wr16(A_SCRIPT_PTR, R_AttractScript);                   /* L0A4B-L0A4E */
    g.cpu_loop = LOOP_MAIN;                                /* falls into MainLoop */
}

/* MainLoop ($0A51): one pass. */
void main_loop_pass(void)
{
    uint16_t hl;
    uint8_t  a;

    g.pass_count++;
    hw_watchdog();                                         /* L0A55 */
    hl = rd16(A_SCRIPT_PTR);                               /* L0A57 */
    a = cpu_rd(hl);                                        /* L0A5A */
    if (a != 0) {                                          /* L0A5B-L0A5C */
        g.iff = 0;                                         /* L0A5F DI */
        hl++;                                              /* L0A60 */
        wr16(A_SCRIPT_PTR, hl);                            /* L0A61 */
        script_command(a, hl);                             /* L0A64-L0A70: DE -> arguments */
        return;                                            /* the handler's RET -> MainLoop */
    }
    /* WAIT: one pass of the game tasks */
    g.iff = 1;                                             /* L0A71 EI */
    handle_contact();                                      /* L0A72 */
    format_scores();                                       /* L0A75 */
    run_timer_events();                                    /* L0A78 */
    run_timer_events2();                                   /* L0A7B */
    check_timeout();                                       /* L0A7E */
    serve_clown();                                         /* L0A81 */
    animate_flyer();                                       /* L0A84 */
    draw_next_digit();                                     /* L0A87 */
    handle_contact();                                      /* L0A8A */
    draw_next_digit();                                     /* L0A8D */
    read_start_buttons();                                  /* L0A90 */
    draw_playfield_if_on();                                /* L0A93 */
    autopilot();                                           /* L0A96 */
    if (GAME_ACTIVE == 0) return;                          /* L0A99-L0A9D */
    draw_next_digit();                                     /* L0A9E */
    check_rows_cleared();                                  /* L0AA1 */
}                                                          /* L0AA4 RET -> MainLoop */

/* Random ($0AA5): next 8-bit pseudo-random number. */
uint8_t random8(void)
{
    uint8_t a = RNG_SEED;                                  /* L0AA5-L0AAA */
    uint8_t b, c = 0x00;                                   /* L0AA8 */
    if (a == 0) a = 0xFF;                                  /* L0AAB-L0AAF */
    b = a;                                                 /* L0AB0 */
    if (!parity_even((uint8_t)(a & 0x1D))) c = 0x80;       /* L0AB1-L0AB6 */
    a = (uint8_t)((b >> 1) & 0x7F);                        /* L0AB8-L0ABA RRC / ANI $7F */
    a = (uint8_t)(a + c);                                  /* L0ABC */
    RNG_SEED = a;                                          /* L0ABD */
    return a;
}

/* AnimateFlyer ($0AD7): choose the flyer's picture and erase mode from its height. */
void animate_flyer(void)
{
    uint16_t de;
    uint8_t  a;

    if (SERVING != 0) return;                              /* L0AD7-L0ADB */
    de = rd16(A_FLYER_PTR);                                /* L0ADC, L0AE2-L0AE3 */
    if (!(cpu_rd(de) & 0x80)) return;                      /* L0ADF-L0AE1 */
    a = cpu_rd((uint16_t)(de + K_CL_Y));                   /* L0AE4-L0AE8 */
    if (a >= 0xBC) return;                                 /* L0AE9-L0AEB */
    if (a >= 0xB0) {                                       /* L0AEC-L0AEE */
        ERASE_MODE = 0x20;                                 /* L0AF1-L0AF3 */
        cpu_wr((uint16_t)(de + K_CL_FRAME), 0);            /* L0AF6-L0AF8 */
        return;
    }
    ERASE_MODE = 0x40;                                     /* L0AFC-L0AFE */
    if (a < 0x54) return;                                  /* L0AFA, L0B01 RC */
    if (TMR_TUMBLE != 0) return;                           /* L0B02-L0B07 */
    TMR_TUMBLE = 0x07;                                     /* L0B08 */
    a = (uint8_t)(cpu_rd((uint16_t)(de + K_CL_FRAME)) + 1);/* L0B0A-L0B0C */
    if (a >= 0x04) a = 0x01;                               /* L0B0D-L0B12 */
    cpu_wr((uint16_t)(de + K_CL_FRAME), a);                /* L0B14 */
}

/* PlayerRow ($0B6D): the balloon address in the current player's rows. */
uint16_t player_row(uint16_t de)
{
    uint16_t hl = de;                                      /* L0B6D */
    if (PLAYER != 0) hl = (uint16_t)(hl + K_P2_OFFSET);    /* L0B6E-L0B76 */
    return hl;
}

/* DrawBalloon ($0B78): 8-row balloon picture DE at screen address HL. */
void draw_balloon(uint16_t de, uint16_t hl)
{
    uint8_t b = 0x08;                                      /* L0B78 */
    do {
        shift_data(cpu_rd(de)); de++;                      /* L0B7A-L0B7C */
        cpu_wr(hl, shift_in()); hl++;                      /* L0B7E-L0B81 */
        shift_data(0);                                     /* L0B82-L0B83 */
        cpu_wr(hl, shift_in());                            /* L0B85-L0B87 */
        hl = (uint16_t)(hl + 0x001F);                      /* L0B89-L0B8C */
    } while (--b != 0);                                    /* L0B8E-L0B8F */
}

/* MoveBalloonsRight ($0B17): six balloons, every other one from DE, one pixel right. */
void move_balloons_right(uint16_t de)
{
    uint16_t hl = player_row(de);                          /* L0B17 */
    uint8_t  n = 0x06;                                     /* L0B1A */
    do {
        if (cpu_rd(hl) & 0x80) {                           /* L0B1D-L0B1F */
            uint8_t e, d;
            cpu_wr((uint16_t)(hl + 1), (uint8_t)(cpu_rd((uint16_t)(hl + 1)) + 1));   /* L0B24 */
            e = cpu_rd((uint16_t)(hl + 1));                /* L0B25-L0B26 */
            shift_amt((uint8_t)(e & 0x07));                /* L0B27-L0B29 */
            d = cpu_rd((uint16_t)(hl + 2));                /* L0B2C */
            draw_balloon(R_BalloonRightPic, screen_addr(d, e));   /* L0B2D-L0B34 */
        }
        hl = (uint16_t)(hl + 0x0006);                      /* L0B38-L0B3B */
    } while (--n != 0);                                    /* L0B3D-L0B3E */
}

/* MoveBalloonsLeft ($0B42): six balloons, every other one from DE, one pixel left. */
void move_balloons_left(uint16_t de)
{
    uint16_t hl = player_row(de);                          /* L0B42 */
    uint8_t  n = 0x06;                                     /* L0B45 */
    do {
        if (cpu_rd(hl) & 0x80) {                           /* L0B48-L0B4A */
            uint8_t e, d;
            cpu_wr((uint16_t)(hl + 1), (uint8_t)(cpu_rd((uint16_t)(hl + 1)) - 1));   /* L0B4F */
            e = cpu_rd((uint16_t)(hl + 1));                /* L0B50-L0B51 */
            shift_amt((uint8_t)(e & 0x07));                /* L0B52-L0B54 */
            d = cpu_rd((uint16_t)(hl + 2));                /* L0B57 */
            draw_balloon(R_BalloonLeftPic, screen_addr(d, e));    /* L0B58-L0B5F */
        }
        hl = (uint16_t)(hl + 0x0006);                      /* L0B63-L0B66 */
    } while (--n != 0);                                    /* L0B68-L0B69 */
}

/* ServeClown ($0BA4): start a new jump when SERVE_REQUEST is set. */
void serve_clown(void)
{
    uint16_t tbl, rider, flyer, hl;
    uint8_t  a, c;

    if (SERVE_REQUEST == 0) return;                        /* L0BA4-L0BA9 */
    SERVE_REQUEST = 0;                                     /* L0BAA */
    a = (uint8_t)((random8() & 0x03) + 1);                 /* L0BAC-L0BB1 */
    tbl = (uint16_t)(R_ServeTable - 6);                    /* L0BB2 */
    do {
        tbl = (uint16_t)(tbl + 0x0006);                    /* L0BB5-L0BB8 */
    } while (--a != 0);                                    /* L0BB9-L0BBA */
    if (PLAYER != 0) { rider = A_CLOWN_B; flyer = A_CLOWN_A; }   /* L0BBE-L0BCC */
    else             { rider = A_CLOWN_A; flyer = A_CLOWN_B; }
    cpu_wr(rider, 0x80);                                   /* L0BCD */
    cpu_wr((uint16_t)(rider + K_CL_Y), 0xC4);              /* L0BD0-L0BD2 */
    wr16(A_RIDER_PTR, rider);                              /* L0BD5 */
    hl = (uint16_t)(flyer + 0x0006);                       /* L0BD8-L0BD9 */
    c = 0x06;
    do {
        hl--;                                              /* L0BDD */
        cpu_wr(hl, cpu_rd(tbl));                           /* L0BDB, L0BDE */
        tbl++;                                             /* L0BDC */
    } while (--c != 0);                                    /* L0BDF-L0BE0 */
    wr16(A_FLYER_PTR, hl);                                 /* L0BE3 */
    TMR_WALK = 0x01;                                       /* L0BE6-L0BE8 */
    SERVING = 0x01;                                        /* L0BEB */
    TMR_SERVE_JUMP = 0x1E;                                 /* L0BEE-L0BF0 */
}

/* NibbleToChar ($0C77): character for the low nibble of A.  (The ROM uses the
 * ADI $90 / DAA / ACI $40 / DAA trick; the result is the same.) */
uint8_t nibble_to_char(uint8_t a)
{
    a &= 0x0F;                                             /* L0C77 */
    return (uint8_t)(a < 10 ? 0x30 + a : 0x37 + a);        /* L0C79-L0C7E */
}

/* BcdToChars ($0C54): the BCD byte at BC as two digit characters at HL. */
static void bcd_to_chars(uint16_t *bc, uint16_t *hl)
{
    cpu_wr(*hl, nibble_to_char((uint8_t)(cpu_rd(*bc) >> 4)));   /* L0C54-L0C58 (HighNibbleToChar $0C73) */
    (*hl)++;                                               /* L0C59 */
    cpu_wr(*hl, nibble_to_char(cpu_rd(*bc)));              /* L0C5A, L0C5C-L0C5F */
    (*bc)++;                                               /* L0C5B */
    (*hl)++;                                               /* L0C60 */
}

/* BlankZeros ($0C80): '0' characters from HL become blanks, up to the first other one. */
static void blank_zeros(uint16_t hl)
{
    while (cpu_rd(hl) == 0x30) {                           /* L0C80-L0C83 */
        cpu_wr(hl, 0x40);                                  /* L0C84 */
        hl++;                                              /* L0C86 */
    }
}

/* FormatScore ($0C62): the 2-byte BCD score at BC as 5 characters at HL. */
void format_score(uint16_t *bc, uint16_t *hl)
{
    uint16_t de = *hl;                                     /* L0C62-L0C63 */
    bcd_to_chars(bc, hl);                                  /* L0C64 */
    bcd_to_chars(bc, hl);                                  /* L0C67 */
    blank_zeros(de);                                       /* L0C6A-L0C6B */
    cpu_wr(*hl, 0x30);                                     /* L0C6F */
    (*hl)++;                                               /* L0C71 */
}

/* FormatScores ($0C0D): both scores and the jumps left into TEXT_BUF; falls
 * into DrawNextDigit. */
void format_scores(void)
{
    uint16_t hl = A_TEXT_BUF, bc = A_P1_SCORE;             /* L0C12-L0C15 */
    if (GAME_ACTIVE == 0) return;                          /* L0C0D-L0C11 */
    format_score(&bc, &hl);                                /* L0C18 */
    cpu_wr(hl, nibble_to_char(cpu_rd(bc)));                /* L0C1B, L0C1D-L0C20: jumps left */
    bc++;                                                  /* L0C1C */
    hl++;                                                  /* L0C21 */
    format_score(&bc, &hl);                                /* L0C22 */
    draw_next_digit();                                     /* falls into $0C25 */
}

/* DrawNextDigit ($0C25): the next character of TEXT_BUF at its place on the score line. */
void draw_next_digit(void)
{
    uint16_t hl, de;
    uint8_t  a, b;

    if (GAME_ACTIVE == 0) return;                          /* L0C25-L0C29 */
    b = 0x06;                                              /* L0C2E */
    if (TWO_PLAYERS != 0) b = 0x0B;                        /* L0C2A-L0C33 */
    a = (uint8_t)(DIGIT_INDEX + 1);                        /* L0C35-L0C39 */
    if (a >= b) a = 0;                                     /* L0C3A-L0C3E */
    DIGIT_INDEX = a;                                       /* L0C3F */
    de = rd16((uint16_t)(R_ScoreLineAddrs + 2 * a));       /* L0C43-L0C4A */
    hl = (uint16_t)(A_TEXT_BUF + a);                       /* L0C4B-L0C4E */
    draw_string(1, &hl, &de);                              /* L0C4F-L0C51 */
}

/* ReadStartButtons ($0CA0). */
void read_start_buttons(void)
{
    uint8_t b = hw_in_switch();                            /* L0CA0-L0CA2 */
    uint8_t a = hw_in_switch();                            /* L0CA3 */
    if (a != b) return;                                    /* L0CA5-L0CA6 */
    START1_DOWN = (uint8_t)(~a & 0x20);                    /* L0CA7-L0CAA */
    START2_DOWN = (uint8_t)(~b & 0x10);                    /* L0CAD-L0CB1 */
}

/* FillRun ($0CDE): write C to B bytes from HL. */
static void fill_run(uint16_t hl, uint8_t b, uint8_t c)
{
    do {
        cpu_wr(hl, c);                                     /* L0CDE */
        hl++;                                              /* L0CDF */
    } while (--b != 0);                                    /* L0CE0-L0CE1 */
}

/* DrawPlayfieldIfOn ($0CB5). */
void draw_playfield_if_on(void)
{
    if (PLAYFIELD_ON == 0) return;                         /* L0CB5-L0CB9 */
    draw_playfield();
}

/* DrawPlayfield ($0CBA): the floor line and the four ledges. */
void draw_playfield(void)
{
    fill_run(0x3E80, 0x20, 0xFF);                          /* L0CBA-L0CC0: floor, line 212 */
    fill_run(0x3700, 0x04, 0xFF);                          /* L0CC3-L0CC8: line 152, left */
    fill_run(0x371C, 0x04, 0xFF);                          /* L0CCB-L0CD0: line 152, right */
    fill_run(0x3300, 0x03, 0xFF);                          /* L0CD3-L0CD6: line 120, left */
    fill_run(0x331D, 0x03, 0xFF);                          /* L0CD9-L0CDC: line 120, right */
}

/* Autopilot ($0CE5): attract mode: put the seesaw under the falling clown. */
void autopilot(void)
{
    uint16_t hl;
    uint8_t  a, b;

    if (AUTOPILOT == 0) return;                            /* L0CE5-L0CE9 */
    if (TMR_HIT_LOCKOUT != 0) return;                      /* L0CEA-L0CEE */
    hl = rd16(A_FLYER_PTR);                                /* L0CEF */
    if (!(cpu_rd(hl) & 0x80)) return;                      /* L0CF2-L0CF4 */
    hl = (uint16_t)(hl + K_CL_X);                          /* L0CF5-L0CF7 */
    b = cpu_rd(hl);                                        /* L0CF8 */
    a = 0xFC;                                              /* L0CFE */
    if (!(SEESAW_STATE & 0x20)) a = 0xE8;                  /* L0CF9-L0D03 */
    a = (uint8_t)(a + cpu_rd(hl));                         /* L0D05 */
    if (a >= 0xE0) {                                       /* L0D06-L0D08 */
        b = (uint8_t)(b + 1);                              /* L0D0B */
        a = 0xD7;                                          /* L0D0C */
        if (!(b & 0x80)) a = 0;                            /* L0D0E-L0D11 */
    }
    PADDLE_POS = a;                                        /* L0D12 */
}

/* CheckRowsCleared ($0D16): award the bonus when the player empties a balloon row. */
void check_rows_cleared(void)
{
    uint16_t hl, de = K_P2_OFFSET;                         /* L0D22 */
    uint8_t  a, b, c;

    if (REFILL_PENDING != 0) return;                       /* L0D16-L0D1A */
    hl = A_P1_ROW_TOP;                                     /* L0D1F */
    if (PLAYER != 0) hl = (uint16_t)(hl + de);             /* L0D1B-L0D28 */
    if (hw_in_dip() & 0x10) {                              /* L0D29-L0D2D */
        /* CheckAllRowsCleared ($0D96) */
        wr16(A_REFILL_ROW_PTR, hl);                        /* L0D96 */
        c = 0x03;                                          /* L0D99 */
        do {
            b = 0x0C;                                      /* L0D9B */
            do {
                a = cpu_rd(hl);                            /* L0D9D */
                if (a & 0x80) return;                      /* L0D9E-L0D9F RM */
                hl = (uint16_t)(hl + 3);                   /* L0DA0-L0DA2 */
            } while (--b != 0);                            /* L0DA3-L0DA4 */
            hl = (uint16_t)(hl + de);                      /* L0DA7 */
        } while (--c != 0);                                /* L0DA8-L0DA9 */
        award_row_bonus((uint8_t)(a + 1), R_AllRowsBonus); /* L0DAC-L0DB0 */
        return;
    }
    c = 0x02;                                              /* L0D30 */
    do {
        uint16_t row = hl;                                 /* L0D32 */
        b = 0x0C;                                          /* L0D33 */
        do {
            if (cpu_rd(hl) & 0x80) break;                  /* L0D35-L0D37 JM L0D8E */
            hl = (uint16_t)(hl + 3);                       /* L0D3A-L0D3C */
        } while (--b != 0);                                /* L0D3D-L0D3E */
        if (b == 0) {                                      /* an empty row */
            wr16(A_REFILL_ROW_PTR, row);                   /* L0D41-L0D42 */
            hl = (uint16_t)(R_RowBonusTable + 3 * c);      /* L0D45-L0D4A */
            a = cpu_rd(hl);                                /* L0D4B */
            award_row_bonus(a, (uint16_t)(hl + 1));        /* L0D4C */
            return;
        }
        hl = (uint16_t)(row + de + de);                    /* L0D8E-L0D90 */
        c = (uint8_t)(c - 1);                              /* L0D91 */
    } while (!(c & 0x80));                                 /* L0D92 JP L0D32 */
}                                                          /* L0D95 */

/* AwardRowBonus ($0D4D): A = REFILL_PENDING value, HL -> the two points bytes. */
static void award_row_bonus(uint8_t a, uint16_t hl)
{
    uint16_t bc, buf, text, scr;

    REFILL_PENDING = a;                                    /* L0D4D */
    TMR_REFILL = 0x96;                                     /* L0D50-L0D52 */
    TMR_FREEZE = 0x5A;                                     /* L0D55-L0D57 */
    FREEZE_REQ = 0x5A;                                     /* L0D5A */
    add_score(cpu_rd(hl), cpu_rd((uint16_t)(hl + 1)));     /* L0D5D-L0D61 */
    bc = hl;                                               /* L0D64 */
    buf = A_BONUS_BUF;                                     /* L0D65 */
    format_score(&bc, &buf);                               /* L0D69 */
    wr16(A_TUNE_PTR, R_BonusTune);                         /* L0D6C-L0D6F */
    text = R_TxtBonus;                                     /* L0D72 */
    scr = 0x3486;                                          /* L0D75 */
    draw_big_string(0x05, &text, &scr);                    /* L0D78-L0D7A */
    text = A_BONUS_BUF;                                    /* L0D7D */
    scr = 0x388D;                                          /* L0D7E */
    if (!(hw_in_dip() & 0x10)) scr--;                      /* L0D81-L0D88 */
    draw_string(0x05, &text, &scr);                        /* L0D89-L0D8B */
}
