/* irq.c - SECTION 2 ($0138-$0475): the two interrupts and what they run.
 *
 * rst1() is the mid-screen interrupt (RST 1, line 96), rst2() the vertical
 * blank interrupt (RST 2, line 224).  Each frame one of them updates the
 * flying clown and the other does the frame task; an interrupt runs to its
 * end with interrupts off and re-enables them on the way out (IrqExit).
 *
 * The clown pointers can be 0 (after a CLEAR, before the first serve): the
 * ROM then reads ROM bytes and its writes go nowhere, so objects are reached
 * through cpu_rd / cpu_wr.
 */
#include "state.h"
#include "hw.h"
#include "game.h"

/* Rst1 ($0008) -> Rst1Handler ($0138): mid-screen interrupt. */
void rst1(void)
{
    uint16_t hl = (uint16_t)(rd16(A_FLYER_PTR) + K_CL_Y);  /* L0138-L013E */
    uint8_t  a = cpu_rd(hl);                               /* L013F */
    if (a < 0x50) a = (uint8_t)(a - 0x50);                 /* L0140-L0142: above line $50, A non-zero */
    else a = 0;                                            /* L0145 */
    FLYER_HIGH = a;                                        /* L0146 */
    if (a == 0) frame_task();                              /* L0149 JZ FrameTask */
    else update_flyer();
    g.iff = 1;                                             /* IrqExit ($01E7): EI / RET */
}

/* UpdateFlyer ($014C): erase, move and redraw the flyer, test for contact; then the tune. */
void update_flyer(void)
{
    if (FREEZE == 0 && CONTACT_ROW == 0) {                 /* L014C-L0157 */
        erase_flyer(rd16(A_FLYER_PTR));                    /* L015A-L015D */
        draw_flyer(rd16(A_FLYER_PTR));                     /* L0160-L0163 */
        FREEZE = FREEZE_REQ;                               /* L0166-L0169 */
        check_contact();                                   /* L016C */
    }
    play_tune();                                           /* L016F */
}                                                          /* L0172 JMP IrqExit */

/* Rst2 ($0010) -> Rst2Handler ($0175): vertical blank interrupt. */
void rst2(void)
{
    uint8_t a;
    if (PADDLE_ENABLE != 0) PADDLE_POS = hw_in_paddle();   /* L0175-L017E */
    a = (uint8_t)((OUT3_SHADOW & 0xFD) | (PLAYER & 0x02)); /* L0181-L018D */
    OUT3_SHADOW = a;                                       /* L018E */
    hw_out_misc(a);                                        /* L018F */
    if (FLYER_HIGH == 0) update_flyer();                   /* L0191-L0195 JZ UpdateFlyer */
    else frame_task();
    g.iff = 1;                                             /* IrqExit */
}

/* FrameTask ($0198): seesaw and rider (even frames) or balloons and timers (odd frames). */
void frame_task(void)
{
    uint8_t a;
    FRAME_CTR = (uint8_t)(FRAME_CTR + 1);                  /* L0198-L019B */
    if (!(FRAME_CTR & 1)) {                                /* L019C-L019E */
        erase_rider(rd16(A_RIDER_PTR));                    /* L01A1-L01A4 */
        erase_seesaw();                                    /* L01A7 */
        draw_seesaw();                                     /* L01AA */
        draw_rider(rd16(A_RIDER_PTR));                     /* L01AD-L01B0 */
        return;                                            /* L01B3 JMP IrqExit */
    }
    /* Odd frame: one of the six balloon passes, then the timers (L01B6 pushes FrameTimers) */
    if (FREEZE == 0) {                                     /* L01BA-L01BE RNZ */
        uint16_t hl, de, fn;
        a = (uint8_t)(BALLOON_PHASE + 1);                  /* L01BF-L01C3 */
        if (a >= 0x06) a = 0;                              /* L01C4-L01C9 */
        BALLOON_PHASE = a;                                 /* L01CA */
        hl = (uint16_t)(R_BalloonTasks + 4 * a);           /* L01CB-L01D4 */
        de = (uint16_t)(ROM(hl) | (ROM(hl + 1) << 8));     /* L01D5-L01D7 */
        fn = (uint16_t)(ROM(hl + 2) | (ROM(hl + 3) << 8)); /* L01D9-L01DC */
        if (fn == R_MoveBalloonsRight) move_balloons_right(de);   /* L01DD PCHL */
        else move_balloons_left(de);
    }
    /* FrameTimers ($01DE) */
    tick_second_timer();                                   /* L01DE */
    tick_timers();                                         /* L01E1 */
    coin_switch();                                         /* L01E4 */
}

/* TickSecondTimer ($01ED): count TMR_TIMEOUT down once every 30 odd frames. */
void tick_second_timer(void)
{
    if (EVT_TIMEOUT != 0) return;                          /* L01ED-L01F2 */
    SECOND_PRESCALE = (uint8_t)(SECOND_PRESCALE - 1);      /* L01F4-L01F7 */
    if (SECOND_PRESCALE != 0) return;                      /* L01F8 */
    SECOND_PRESCALE = 0x1E;                                /* L01F9 */
    EVT_TIMEOUT = tick_timer_list(A_TMR_TIMEOUT, 1, 0);    /* L01FB-L0203 */
}

/* TickTimers ($0205): count the 30 Hz timers down and post the ones that reach zero. */
void tick_timers(void)
{
    if (EVT_TIMERS != 0) return;                           /* L0205-L020D */
    EVT_TIMERS = tick_timer_list(A_TMR_SCRIPT, 8, 0);      /* L020E-L0214 */
    if (EVT_TIMERS2 != 0) return;                          /* L0215-L021A */
    EVT_TIMERS2 = tick_timer_list(A_TMR_COIN_CTR, 3, 0);   /* L021B-L0221 */
}

/* TickTimerList ($0223): decrement C timers at HL; shift a 1 into B for each that reaches zero. */
uint8_t tick_timer_list(uint16_t hl, uint8_t c, uint8_t b)
{
    do {
        unsigned cy = 0;                                   /* L0224 ANA A clears the carry */
        if (MEM(hl) != 0) {                                /* L0223-L0225 */
            MEM(hl) = (uint8_t)(MEM(hl) - 1);              /* L0228 */
            if (MEM(hl) == 0) cy = 1;                      /* L0229-L022C STC */
        }
        b = (uint8_t)((b << 1) | cy);                      /* L022D-L022F RAL */
        hl++;                                              /* L0230 */
    } while (--c != 0);                                    /* L0231-L0232 */
    return b;                                              /* L0235 */
}

/* PlayTune ($0237): step the tune player, once a frame. */
void play_tune(void)
{
    uint16_t hl;
    uint8_t  a, b, c;

    if (TUNE_ON == 0) return;                              /* L0237-L023B */
    if (TUNE_TICKS != 0) {                                 /* L023C-L0241 */
        TUNE_TICKS = (uint8_t)(TUNE_TICKS - 1);            /* L0244 */
        return;
    }
    if (TUNE_BEATS != 0) {                                 /* L0246-L0249 */
        TUNE_BEATS = (uint8_t)(TUNE_BEATS - 1);            /* L024C */
        TUNE_TICKS = TUNE_TEMPO;                           /* L024D-L0251 */
        return;
    }
    if (TUNE_GAP != 0) {                                   /* L0253-L0256 */
        TUNE_GAP = (uint8_t)(TUNE_GAP - 1);                /* L0259 */
        hw_tone_lo(0);                                     /* L025A-L025B */
        return;
    }
    hl = rd16(A_TUNE_PTR);                                 /* L025E */
    a = cpu_rd(hl);                                        /* L0261 */
    if (a == 0) {                                          /* L0262-L0263 */
        hw_tone_lo(0);                                     /* L0266-L0267: end of tune */
        if (GAME_ACTIVE != 0) return;                      /* L0269-L026D */
        hw_sound(0);                                       /* L026E: A = GAME_ACTIVE = 0 */
        return;
    }
    if (a & 0x80) {                                        /* L0271 JP L027F */
        TUNE_TEMPO = (uint8_t)(a & 0x7F);                  /* L0274-L0276 */
        hw_sound(0x08);                                    /* L0279-L027B */
        hl++;                                              /* L027D */
        a = cpu_rd(hl);                                    /* L027E */
    }
    TUNE_BEATS = a;                                        /* L027F */
    hl++;                                                  /* L0282 */
    b = TUNE_TEMPO;                                        /* L0283-L0286 */
    a = cpu_rd(hl);                                        /* L0287 */
    if (!(a & 0x80)) {                                     /* L0288-L0289 JM L0292 */
        TUNE_GAP = 1;                                      /* L028C-L028E */
        b = (uint8_t)(b - 1);                              /* L0291 */
    }
    TUNE_TICKS = b;                                        /* L0292-L0293 */
    a = cpu_rd(hl);                                        /* L0296 */
    hl++;                                                  /* L0297 */
    wr16(A_TUNE_PTR, hl);                                  /* L0298 */
    c = (uint8_t)(a & 0x7F);                               /* L029B-L029D */
    /* Program the tone generator with note C */
    hl = (uint16_t)(R_NoteTable + 2 * c);                  /* L029E-L02A4 */
    hw_tone_lo(cpu_rd(hl));                                /* L02A5-L02A6 */
    hw_tone_hi(cpu_rd((uint16_t)(hl + 1)));                /* L02A8-L02AA */
}

/* DrawSeesaw ($02FB): animate and draw the seesaw. */
void draw_seesaw(void)
{
    uint16_t hl, de;
    uint8_t  b, c, e;
    int      i;

    if (!(SEESAW_STATE & 0x80)) return;                    /* L02FB-L0300 */
    if (SEESAW_STATE & 0x40) {                             /* L0301-L0304 */
        int tipped;
        if (SEESAW_STATE & 0x20) {                         /* L0307-L030A */
            SEESAW_STATE = (uint8_t)(SEESAW_STATE + 1);    /* L030D */
            tipped = (SEESAW_STATE & 0x0F) >= 0x04;        /* L030E-L0313 */
        } else {
            SEESAW_STATE = (uint8_t)(SEESAW_STATE - 1);    /* L031F */
            tipped = (SEESAW_STATE & 0x0F) == 0;           /* L0320-L0323 */
        }
        if (tipped)                                        /* L0316-L031B */
            SEESAW_STATE = (uint8_t)((SEESAW_STATE & 0xBF) ^ 0x20);
    }
    c = (uint8_t)(SEESAW_STATE & 0x0F);                    /* L0326-L0329 */
    e = SEESAW_DRAWN_X;                                    /* L032C-L032E */
    shift_amt((uint8_t)(e & 0x07));                        /* L032F-L0331 */
    hl = (uint16_t)(0x3E00 | (((e >> 3) & 0x1F) | 0x60));  /* L0333-L033C: line 211 */
    de = rd16((uint16_t)(R_SeesawPictures + 2 * c));       /* L033E-L0347 */
    b = cpu_rd(de);                                        /* L0348: rows */
    de++;                                                  /* L0349 */
    do {
        for (i = 0; i < 5; i++) {                          /* L034B-L0357: ShiftedByte ($036B) x 5 */
            shift_data(cpu_rd(de));                        /* L036B-L036D */
            de++;                                          /* L036C */
            cpu_wr(hl, shift_in());                        /* L036F-L0371 */
            hl++;                                          /* L0372 */
        }
        shift_data(0);                                     /* L035A-L035B */
        cpu_wr(hl, shift_in());                            /* L035D-L035F */
        hl = (uint16_t)(hl + 0xFFDB);                      /* L0361-L0364: one line up */
    } while (--b != 0);                                    /* L0366-L0367 */
}

/* CoinSwitch ($041F): count a coin on the press edge of the coin switch. */
void coin_switch(void)
{
    uint8_t b = (uint8_t)(~hw_in_switch() & 0x40);         /* L0422-L0427 */
    if ((b ^ COIN_SW_PREV) == 0) return;                   /* L0428-L0429 */
    COIN_SW_PREV = b;                                      /* L042A */
    if (b == 0) return;                                    /* L042B-L042D */
    OUT3_SHADOW = (uint8_t)(OUT3_SHADOW | 0x01);           /* L042E-L0434 */
    TMR_COIN_CTR = 0x0A;                                   /* L0435-L0437 */
    COINS = (uint8_t)(COINS + 1);                          /* L043A-L043D */
}

/* CheckContact ($043F): did the flyer's last picture touch anything? */
void check_contact(void)
{
    uint16_t hl;
    uint8_t  a, b, c;

    if (TMR_HIT_LOCKOUT != 0) return;                      /* L043F-L0443 */
    hl = rd16(A_FLYER_PTR);                                /* L0444 */
    a = cpu_rd(hl);                                        /* L0447 */
    if (!(a & 0x80)) return;                               /* L0448-L0449 */
    if ((a & 0x60) == 0) return;                           /* L044A-L044C */
    if (cpu_rd(hl) & 0x08) return;                         /* L044D-L0450 */
    hl = (uint16_t)(hl + K_CL_ROWS);                       /* L0451-L0454 */
    c = cpu_rd(hl);                                        /* L0455 */
    b = c;                                                 /* L0456 */
    hl = (uint16_t)(hl + 2);                               /* L0457-L0458 */
    do {
        a = (uint8_t)(cpu_rd(hl) & 0xF0);                  /* L0459-L045A */
        hl++;                                              /* L045C */
        a |= cpu_rd(hl);                                   /* L045D */
        if (a != 0) goto contact;                          /* L045E */
        hl++;                                              /* L0461 */
        if (cpu_rd(hl) & 0x0F) goto contact;               /* L0462-L0465 */
        hl++;                                              /* L0468 */
    } while (--b != 0);                                    /* L0469-L046A */
    return;                                                /* L046D */
contact:
    CONTACT_ROW = (uint8_t)(c - b + 1);                    /* L046E-L0471 */
}
