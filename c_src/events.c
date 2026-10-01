/* events.c - SECTION 6 ($117B-$1348): timer events.
 *
 * The interrupt counts the timers down (irq.c) and posts expiries as bits;
 * the main loop picks the bits up here and calls one routine per timer.
 */
#include "state.h"
#include "hw.h"
#include "game.h"

/* CheckTimeout ($117B): if TMR_TIMEOUT has run out, send the script to TIMEOUT_PTR. */
void check_timeout(void)
{
    uint8_t a = EVT_TIMEOUT;                               /* L117B-L117E */
    if (a == 0) return;                                    /* L117F-L1180 */
    EVT_TIMEOUT = 0;                                       /* L1181 */
    if (a & 0x01) script_timeout();                        /* L1183-L1185 */
}

/* ScriptTimeout ($118A): SCRIPT_PTR = TIMEOUT_PTR, unless TIMEOUT_HOLD. */
void script_timeout(void)
{
    if (TIMEOUT_HOLD != 0) return;                         /* L118A-L118E */
    wr16(A_SCRIPT_PTR, rd16(A_TIMEOUT_PTR));               /* L118F-L1192 */
}

/* RunTimerEvents ($1196): call the handler of every 30 Hz timer that has expired. */
void run_timer_events(void)
{
    uint8_t a = EVT_TIMERS;                                /* L1196-L1199 */
    if (a == 0) return;                                    /* L119A-L119B */
    EVT_TIMERS = 0;                                        /* L119C */
    if (a & 0x01) refill_rows();                           /* L119E-L11A0  b0 TMR_REFILL */
    /* L11A4: b1 TMR_HIT_LOCKOUT has no handler */
    if (a & 0x04) splat_step();                            /* L11A5-L11A7  b2 TMR_SPLAT */
    if (a & 0x08) gravity_tick();                          /* L11AB-L11AD  b3 TMR_GRAVITY */
    if (a & 0x10) serve_jump();                            /* L11B1-L11B3  b4 TMR_SERVE_JUMP */
    if (a & 0x20) walk_step();                             /* L11B7-L11B9  b5 TMR_WALK */
    if (a & 0x40) sound_off();                             /* L11BD-L11BF  b6 TMR_SOUND_OFF */
    if (a & 0x80) script_timer_done();                     /* L11C3-L11C5  b7 TMR_SCRIPT */
}

/* SplatStep ($11CA): next of the three splat pictures, then SplatDone. */
void splat_step(void)
{
    uint16_t hl;
    SPLAT_CTR = (uint8_t)(SPLAT_CTR - 1);                  /* L11CA-L11CD */
    if (SPLAT_CTR == 0) {                                  /* L11CE */
        splat_done();
        return;
    }
    TMR_SPLAT = 0x02;                                      /* L11D1-L11D3 */
    hl = (uint16_t)(rd16(A_FLYER_PTR) + K_CL_FRAME);       /* L11D6-L11D9 */
    cpu_wr(hl, (uint8_t)(cpu_rd(hl) + 1));                 /* L11DA */
}

/* SplatDone ($11DC): the jump is over: next turn, next player or game over. */
void splat_done(void)
{
    uint16_t hl = rd16(A_FLYER_PTR);                       /* L11DC */
    uint8_t  a;

    cpu_wr((uint16_t)(hl + K_CL_XVEL), 0);                 /* L11DF-L11E2 */
    cpu_wr((uint16_t)(hl + K_CL_YVEL), 0);                 /* L11E3-L11E5 */
    cpu_wr((uint16_t)(hl + K_CL_Y), 0xDC);                 /* L11E6-L11E7 */
    if (GAME_ACTIVE == 0) {                                /* L11E9-L11ED */
        demo_over();
        return;
    }
    if (JUMPS_AGAIN == 0) {                                /* L11F0-L11F4 */
        if (TWO_PLAYERS != 0) {                            /* L11F7-L11FB */
            a = (uint8_t)(PLAYER ^ 0xFF);                  /* L11FE-L1201 */
            NEXT_PLAYER = a;                               /* L1203 */
            if (a != 0) goto next_turn;                    /* L1206 */
        }
        a = (uint8_t)(JUMPS_LEFT - 1);                     /* L1209-L120C */
        if (a == 0) {                                      /* L120D */
            game_over();
            return;
        }
        NEXT_JUMPS_LEFT = a;                               /* L1210 */
    }
next_turn:                                                 /* NextTurn ($1213) */
    TMR_SCRIPT = 0x01;                                     /* L1213-L1215 */
}

/* GameOver ($1219): back to the attract script; tune; high score. */
void game_over(void)
{
    PREV_BONUS_GAME = BONUS_GAME;                          /* L1219-L121C */
    wr16(A_SCRIPT_PTR, R_AttractScript);                   /* L121F-L1222 */
    wr16(A_TUNE_PTR, R_GameOverTune);                      /* L1225-L1228 */
    check_high_score(A_P1_SCORE, A_HI_SCORE);              /* L122B-L1231 */
    check_high_score(A_P1_SCORE + 3, A_HI_SCORE);          /* L1234-L1236: player 2, falls in */
}

/* CheckHighScore ($1237): if the BCD score at DE beats the one at HL, copy it there. */
void check_high_score(uint16_t de, uint16_t hl)
{
    uint8_t a = cpu_rd(de);                                /* L1237 */
    if (a < cpu_rd(hl)) return;                            /* L1238-L1239 */
    if (a == cpu_rd(hl)) {                                 /* L123A */
        if (cpu_rd((uint16_t)(de + 1)) < cpu_rd((uint16_t)(hl + 1))) return;   /* L123D-L1243 */
    }
    /* CopyScore ($1244) */
    cpu_wr(hl, cpu_rd(de));                                /* L1244-L1246 */
    cpu_wr((uint16_t)(hl + 1), cpu_rd((uint16_t)(de + 1)));/* L1247-L124A */
}

/* DemoOver ($124D): attract mode splat: restart the demo one second from now. */
void demo_over(void)
{
    TMR_TIMEOUT = 0x01;                                    /* L124D-L124F */
    SCRIPT_HOLD = 0x01;                                    /* L1252 */
}

/* GravityTick ($1256): flyer YVEL + 1; restart the timer from GRAVITY_PERIOD. */
void gravity_tick(void)
{
    if (SERVING == 0 && FREEZE_REQ == 0) {                 /* L1256-L1261 */
        uint16_t hl = rd16(A_FLYER_PTR);                   /* L1264 */
        if (cpu_rd(hl) & 0x08) return;                     /* L1267-L126A: splatted, timer left stopped */
        hl = (uint16_t)(hl + K_CL_YVEL);                   /* L126B-L126E */
        cpu_wr(hl, (uint8_t)(cpu_rd(hl) + 1));             /* L126F */
    }
    TMR_GRAVITY = GRAVITY_PERIOD;                          /* RestartGravity ($1270) */
}

/* ServeJump ($1277): the served clown jumps off its ledge. */
void serve_jump(void)
{
    uint16_t hl = rd16(A_FLYER_PTR);                       /* L1277 */
    cpu_wr(hl, (uint8_t)(cpu_rd(hl) & 0xEF));              /* L127A-L127D */
    cpu_wr((uint16_t)(hl + K_CL_FRAME), 0x01);             /* L127E-L1281 */
    TMR_GRAVITY = 0x01;                                    /* L1282 */
    cpu_wr((uint16_t)(hl + K_CL_YVEL), 0xFE);              /* L1285-L1288 */
    SERVING = 0;                                           /* L128A-L128B */
}

/* WalkStep ($128F): every 3 ticks, step the walking clown's picture +1 +1 -1 -1. */
void walk_step(void)
{
    uint16_t hl;
    uint8_t  a;
    int      pe;

    if (SERVING == 0) return;                              /* L128F-L1293 */
    TMR_WALK = 0x03;                                       /* L1294-L1296 */
    hl = rd16(A_FLYER_PTR);                                /* L1299 */
    a = (uint8_t)(WALK_PHASE + 1);                         /* L129C-L12A0 */
    if (a < 0x04) {                                        /* L12A1-L12A3 */
        pe = parity_even((uint8_t)(a - 0x04));             /* the P flag CPI $04 leaves */
    } else {
        a = 0;                                             /* L12A6 XRA A: parity even */
        pe = 1;
    }
    WALK_PHASE = a;                                        /* L12A7 */
    a = 0x01;                                              /* L12A8 */
    if (pe) a = 0xFF;                                      /* L12AA-L12AD JPO L12AF */
    hl = (uint16_t)(hl + K_CL_FRAME);                      /* L12AF */
    cpu_wr(hl, (uint8_t)(a + cpu_rd(hl)));                 /* L12B0-L12B1 */
}

/* ScriptTimerDone ($12B3): step the script past the WAIT it is on, unless SCRIPT_HOLD. */
void script_timer_done(void)
{
    if (SCRIPT_HOLD != 0) return;                          /* L12B3-L12B7 */
    wr16(A_SCRIPT_PTR, (uint16_t)(rd16(A_SCRIPT_PTR) + 1));/* L12B8-L12BC */
}

/* SoundOff ($12C0): end the pop / hit / miss sound, leave the board enabled. */
void sound_off(void)
{
    hw_sound(0x08);                                        /* L12C0-L12C2 */
}

/* RunTimerEvents2 ($12C5): the handlers of the second timer group. */
void run_timer_events2(void)
{
    uint8_t a = EVT_TIMERS2;                               /* L12C5-L12C8 */
    if (a == 0) return;                                    /* L12C9-L12CA */
    EVT_TIMERS2 = 0;                                       /* L12CB */
    if (a & 0x01) end_freeze();                            /* L12CD-L12CF  b0 TMR_FREEZE */
    /* L12D3: b1 TMR_TUMBLE has no handler */
    if (a & 0x04) coin_counter_off();                      /* L12D4-L12D6  b2 TMR_COIN_CTR */
}

/* RefillRows ($12DB): put back the balloons of the cleared row(s). */
void refill_rows(void)
{
    uint16_t hl = rd16(A_REFILL_ROW_PTR);                  /* L12DB */
    uint8_t  b;

    if (hw_in_dip() & 0x10) {                              /* L12DE-L12E2 */
        REFILL_PENDING = 0;                                /* L12E5-L12E6 */
        hl = fill_balloon_row(hl, 0x24);                   /* L12E9-L12EE */
        hl = (uint16_t)(hl + K_P2_OFFSET);                 /* L12F1-L12F4 */
        hl = fill_balloon_row(hl, 0x38);                   /* L12F5-L12F7 */
        hl = (uint16_t)(hl + K_P2_OFFSET);                 /* L12FA-L12FD */
        fill_balloon_row(hl, 0x4E);                        /* L12FE-L1300 */
        return;
    }
    b = REFILL_PENDING;                                    /* L1303-L1307 */
    REFILL_PENDING = 0;                                    /* L1308-L1309 */
    fill_balloon_row(hl, b);                               /* L130A */
}

/* EndFreeze ($130D): let flyer and balloons move again, erase the BONUS message. */
void end_freeze(void)
{
    uint16_t hl, text, scr;

    if (GAME_ACTIVE == 0) return;                          /* L130D-L1311 */
    FREEZE_REQ = 0;                                        /* L1312-L1313 */
    FREEZE = 0;                                            /* L1316 */
    hl = (uint16_t)(rd16(A_FLYER_PTR) + K_CL_Y);           /* L1319-L131F */
    if (cpu_rd(hl) < 0x60) {                               /* L1320-L1323 */
        cpu_wr((uint16_t)(hl - 1), 0);                     /* L1326-L1327: YVEL */
        cpu_wr((uint16_t)(hl - 3), 0);                     /* L1328-L132A: XVEL */
    }
    text = R_TxtBlanks;                                    /* L132B */
    scr = 0x3486;                                          /* L132F */
    draw_big_string(0x05, &text, &scr);                    /* L1332-L1334 */
    text = R_TxtBlanks;                                    /* L1337 */
    scr = 0x388D;                                          /* L1338 */
    draw_string(0x05, &text, &scr);                        /* L133B-L133D */
}

/* CoinCounterOff ($1340): end the coin counter pulse. */
void coin_counter_off(void)
{
    OUT3_SHADOW = (uint8_t)(OUT3_SHADOW & 0xFE);           /* L1340-L1346 */
}
