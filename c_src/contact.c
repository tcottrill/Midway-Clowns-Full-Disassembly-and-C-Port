/* contact.c - SECTION 9 ($1526-$17FF): contact handling and scoring.
 *
 * CheckContact (interrupt, irq.c) reports that the flyer's picture was drawn
 * over something; here the main loop works out what: floor, seesaw, ledge or
 * balloon.
 */
#include "state.h"
#include "hw.h"
#include "game.h"

static void land_on_seesaw(uint8_t e);
static void contact_above(uint8_t a, uint8_t e);
static void ledge_bounce(void);
static void contact_balloons(uint8_t a, uint8_t e);
static void pop_balloon(uint16_t hl, uint8_t row, uint8_t d, uint8_t e);
static uint8_t launch_x_speed(uint8_t a, uint8_t *d);

/* HandleContact ($1526): act on CONTACT_ROW. */
void handle_contact(void)
{
    uint16_t hl;
    uint8_t  a, b, e;

    b = CONTACT_ROW;                                       /* L1526-L152B */
    if (b == 0) return;                                    /* L1529-L152A */
    hl = rd16(A_FLYER_PTR);                                /* L152C */
    if (cpu_rd(hl) & 0x08) return;                         /* L152F-L1532 */
    e = cpu_rd((uint16_t)(hl + K_CL_X));                   /* L1533-L1536 */
    a = (uint8_t)(b + cpu_rd((uint16_t)(hl + K_CL_Y)));    /* L1537-L153A: height of the contact */
    if (a >= 0xD4) {                                       /* L153B-L153D */
        splat(e);
        return;
    }
    /* ContactNotFloor ($15AC) */
    if (a < 0xB0) {                                        /* L15AC-L15AE */
        contact_above(a, e);
        return;
    }
    land_on_seesaw(e);
}

/* Splat ($1540): the flyer hits the floor (or the wrong part of the seesaw).  E = flyer X. */
void splat(uint8_t e)
{
    uint16_t hl = rd16(A_FLYER_PTR);                       /* L1540 */
    uint16_t text, scr;
    uint8_t  a, c;

    cpu_wr((uint16_t)(hl + K_CL_Y), 0xD4);                 /* L1543-L1547 */
    cpu_wr((uint16_t)(hl + K_CL_YVEL), 0x01);              /* L1549-L154A */
    cpu_wr((uint16_t)(hl + K_CL_XVEL), 0x00);              /* L154C-L154E */
    cpu_wr((uint16_t)(hl + K_CL_FRAME), 0x0F);             /* L154F-L1550 */
    cpu_wr(hl, (uint8_t)(cpu_rd(hl) | 0x08));              /* L1552-L1556 */
    ERASE_MODE = 0x40;                                     /* L1557-L1559 */
    TMR_SPLAT = 0x03;                                      /* L155C-L155E */
    SPLAT_CTR = 0x03;                                      /* L1561 */
    c = (uint8_t)(random8() & 0x03);                       /* L1564-L1569 */
    text = (uint16_t)(R_SplatWords + 3 * c);               /* L156A-L1571 */
    a = e;                                                 /* L1572 */
    if (a >= 0x08) a = (uint8_t)(a - 0x08);                /* L1573-L1578 */
    if (a >= 0xF0) a = 0xE8;                               /* L157A-L157F */
    scr = (uint16_t)(0x3800 | ((a >> 3) & 0x1F));          /* L1581-L1587: line 160 */
    draw_string(0x03, &text, &scr);                        /* L1589-L158B */
    CONTACT_ROW = 0;                                       /* L158E: A = 0 from DrawString */
    if (GAME_ACTIVE == 0) return;                          /* L1591-L1595 */
    hw_sound(0x28);                                        /* L1596-L1598: miss */
    TMR_SOUND_OFF = 0x07;                                  /* L159A-L159C */
}

/* LandOnSeesaw ($15B1): launch the rider if the flyer came down on the raised end. */
static void land_on_seesaw(uint8_t e)
{
    uint16_t hl, old_rider;
    uint8_t  a, c, d, xvel;

    d = 0x00;                                              /* L15B7 */
    if (!(SEESAW_STATE & 0x20)) d = 0x14;                  /* L15B1-L15BC */
    a = (uint8_t)(e + 0x0C - d - SEESAW_DRAWN_X);          /* L15BE-L15C3 */
    if (a >= 0x1C) {                                       /* L15C4-L15C6 */
        splat(e);
        return;
    }
    c = (uint8_t)((a >> 2) & 0x07);                        /* L15C9-L15CD */
    SEESAW_STATE = (uint8_t)(SEESAW_STATE | 0x40);         /* L15CE-L15D2: start tipping */
    old_rider = rd16(A_RIDER_PTR);                         /* L15D5-L15D8 */
    hl = rd16(A_FLYER_PTR);                                /* L15D9 */
    cpu_wr(hl, 0xA0);                                      /* L15DC */
    wr16(A_RIDER_PTR, hl);                                 /* L15DE: it is the rider now */
    cpu_wr((uint16_t)(hl + K_CL_XVEL), 0);                 /* L15E1-L15E3 */
    cpu_wr((uint16_t)(hl + K_CL_YVEL), 0);                 /* L15E4-L15E6 */
    cpu_wr((uint16_t)(hl + K_CL_Y), 0xC4);                 /* L15E7-L15E8 */
    a = (uint8_t)(c - 0x03);                               /* L15EA-L15EB */
    if (a == 0) {                                          /* L15ED */
        xvel = 0;                                          /* L15F0 */
        d = (uint8_t)(SPEED_LEVEL + 0x05);                 /* L15F1-L15F6 */
    } else if (c >= 0x03) {                                /* L15FA JNC L1608: right of the middle */
        xvel = launch_x_speed(a, &d);                      /* L1608-L160B */
    } else {
        a = (uint8_t)(0 - a);                              /* L15FD-L15FE */
        xvel = (uint8_t)(0 - launch_x_speed(a, &d));       /* L15FF-L1604 */
    }
    a = (uint8_t)(0 - d);                                  /* L160C-L160E: YVEL = -speed */
    hl = (uint16_t)(old_rider + K_CL_YVEL);                /* L160F-L1612 */
    cpu_wr(hl, a);                                         /* L1613 */
    hl--;                                                  /* L1614: CL_X */
    if (cpu_rd(hl) >= 0xF2) cpu_wr(hl, 0xF1);              /* L1615-L161B */
    hl--;                                                  /* L161D */
    cpu_wr(hl, xvel);                                      /* L161E */
    hl = (uint16_t)(hl - 2);                               /* L161F-L1620 */
    cpu_wr(hl, 0xA0);                                      /* L1621 */
    wr16(A_FLYER_PTR, hl);                                 /* L1623: it is the flyer now */

    REBOUND_STEP_CTR = (uint8_t)(REBOUND_STEP_CTR + 1);    /* L1626-L1629 */
    if (REBOUND_STEP_CTR >= 0x04) {                        /* L162A-L162D */
        REBOUND_STEP_CTR = 0;                              /* L1630 */
        REBOUND_SPEED = (uint8_t)(REBOUND_SPEED + 1);      /* L1631-L1634 */
        if (REBOUND_SPEED >= 0x05) REBOUND_SPEED = 0x04;   /* L1635-L163B */
    }
    GRAVITY_STEP_CTR = (uint8_t)(GRAVITY_STEP_CTR + 1);    /* L163D-L1640 */
    if (GRAVITY_STEP_CTR >= 0x02) {                        /* L1641-L1644 */
        GRAVITY_STEP_CTR = 0;                              /* L1647 */
        GRAVITY_PERIOD = (uint8_t)(GRAVITY_PERIOD + 1);    /* L1648-L164B */
        if (GRAVITY_PERIOD >= 0x09) GRAVITY_PERIOD = 0x08; /* L164C-L1652 */
    }
    SPEED_STEP_CTR = (uint8_t)(SPEED_STEP_CTR + 1);        /* L1654-L1657 */
    if (SPEED_STEP_CTR >= 0x03) {                          /* L1658-L165B */
        SPEED_STEP_CTR = 0;                                /* L165E */
        a = (uint8_t)(SPEED_LEVEL + 1);                    /* L165F-L1663 */
        if (a >= 0x05) a = 0x04;                           /* L1664-L1669 */
        SPEED_LEVEL = a;                                   /* L166B */
    }
    TMR_HIT_LOCKOUT = 0x03;                                /* L166C-L166E */
    clear_contact();                                       /* L1671 */
    if (GAME_ACTIVE == 0) return;                          /* L1674-L1678 */
    hw_sound(0x18);                                        /* L1679-L167B: springboard */
    TMR_SOUND_OFF = 0x07;                                  /* L167D-L167F */
    add_score(0x00, 0x01);                                 /* L1682: 10 points, falls into AddScore */
}

/* AddScore ($1685): add BC (BCD, tens of points) to the current player's
 * score; award the bonus game and the extra jump. */
void add_score(uint8_t b, uint8_t c)
{
    uint16_t hl, de, text, scr;
    uint8_t  a;
    unsigned cy;

    if (GAME_ACTIVE == 0) return;                          /* L1685-L1689 */
    hl = A_P1_EXTRA_JUMP;                                  /* L168E */
    de = A_P1_SCORE + 1;                                   /* L1691 */
    if (PLAYER != 0) {                                     /* L168A-L1694 */
        hl++;                                              /* L1697 */
        de = A_P2_SCORE + 1;                               /* L1698 */
    }
    cy = 0;
    cpu_wr(de, add_daa(cpu_rd(de), c, &cy));               /* L169B-L169E: low byte */
    de--;                                                  /* L169F */
    b = add_daa(cpu_rd(de), b, &cy);                       /* L16A0-L16A2: high byte */
    cpu_wr(de, b);                                         /* L16A3-L16A4 */

    if (PREV_BONUS_GAME == 0 && BONUS_GAME == 0) {         /* L16A5-L16B1 */
        a = (uint8_t)(hw_in_dip() & 0x0C);                 /* L16B4-L16B6 */
        if (a != 0) {                                      /* L16B8 */
            cy = 0;
            a = add_daa((uint8_t)(a >> 1), 0x06, &cy);     /* L16BB-L16BE: 8, $10, $12 */
            if (a < b) {                                   /* L16BF-L16C0 */
                a = COINS_PER_GAME;                        /* L16C3-L16C6 */
                BONUS_GAME = a;                            /* L16C8 */
                COINS = (uint8_t)(a + COINS);              /* L16C7, L16C9-L16CA */
                text = R_TxtAdditionalGame;                /* L16CB */
                scr = 0x3E88;                              /* L16CE */
                draw_string(0x0F, &text, &scr);            /* L16D1-L16D3 */
                return;
            }
        }
    }
    /* CheckExtraJump ($16D6) */
    c = 0x03;                                              /* L16DA */
    if (hw_in_dip() & 0x20) c = 0x04;                      /* L16D6-L16DF */
    if (b < c) return;                                     /* L16E0-L16E2 */
    if (cpu_rd(hl) != 0) return;                           /* L16E3-L16E5 */
    cpu_wr(hl, (uint8_t)(cpu_rd(hl) + 1));                 /* L16E6 */
    wr16(A_TUNE_PTR, R_BonusTune);                         /* L16E7-L16EA */
    TMR_FREEZE = 0x5A;                                     /* L16ED-L16EF */
    FREEZE_REQ = 0x5A;                                     /* L16F2 */
    JUMPS_AGAIN = 0x5A;                                    /* L16F5 */
    text = R_TxtBonus;                                     /* L16F8 */
    scr = 0x3486;                                          /* L16FB */
    draw_big_string(0x05, &text, &scr);                    /* L16FE-L1700 */
    text = R_TxtPlayerJumpsAgain;                          /* L1703 */
    scr = 0x3E87;                                          /* L1706 */
    draw_string(0x12, &text, &scr);                        /* L1709-L170B */
}

/* LaunchXSpeed ($170E): A = distance from the middle of the zone (1-3).
 * Returns the X speed; *d = launch speed. */
static uint8_t launch_x_speed(uint8_t a, uint8_t *d)
{
    uint8_t e = a;                                         /* L170E */
    a = 0;                                                 /* L170F */
    do {
        a = (uint8_t)(a + 0x03);                           /* L1710 */
    } while (--e != 0);                                    /* L1712-L1713 */
    e = a;                                                 /* L1716 */
    *d = (uint8_t)(SPEED_LEVEL + 0x05);                    /* L1717-L171C */
    a = 0;                                                 /* L171D */
    do {
        a = (uint8_t)(a + *d);                             /* L171E */
    } while (--e != 0);                                    /* L171F-L1720 */
    return (uint8_t)((a >> 4) & 0x0F);                     /* L1723-L1727 */
}

/* ContactAbove ($172A): contact above the seesaw zone. */
static void contact_above(uint8_t a, uint8_t e)
{
    if (a < 0x5C) {                                        /* L172A-L172C */
        contact_balloons(a, e);
        return;
    }
    if (e >= 0x18 && e < 0xD8) {                           /* L172F-L1737 */
        clear_contact();
        return;
    }
    ledge_bounce();
}

/* LedgeBounce ($173A): bounce a falling flyer up and away from the wall. */
static void ledge_bounce(void)
{
    uint16_t hl = (uint16_t)(rd16(A_FLYER_PTR) + K_CL_YVEL);   /* L173A-L1740 */
    uint8_t  x;

    clear_contact();                                       /* L1741 */
    if (cpu_rd(hl) & 0x80) return;                         /* L1744-L1746: going up */
    cpu_wr(hl, 0xFE);                                      /* L1747 */
    x = cpu_rd((uint16_t)(hl - 1));                        /* L1749-L174B */
    cpu_wr((uint16_t)(hl - 2), 0x01);                      /* L174C-L174D */
    if (x & 0x80) cpu_wr((uint16_t)(hl - 2), 0xFF);        /* L174F-L1752 */
    cpu_wr((uint16_t)(hl - 3), 0x10);                      /* L1754-L1755: crouched */
}

/* ContactBalloons ($1758): find the balloon row by height. */
static void contact_balloons(uint8_t a, uint8_t e)
{
    if (a >= 0x4E) { pop_balloon(A_P1_ROW_BOT, 0, 0x4E, e); return; }   /* L1758-L1760 */
    if (a >= 0x38) { pop_balloon(A_P1_ROW_MID, 1, 0x38, e); return; }   /* L1763-L176A */
    if (a >= 0x24) { pop_balloon(A_P1_ROW_TOP, 2, 0x24, e); return; }   /* L176D-L1774 */
    clear_contact();                                       /* falls into ClearContact */
}

/* ClearContact ($1777). */
void clear_contact(void)
{
    CONTACT_ROW = 0;                                       /* L1777-L1778 */
}

/* PopBalloon ($177C): find the balloon the flyer touched in row HL and pop it.
 * row = B (0 bottom .. 2 top), d = the row's Y, e = flyer X. */
static void pop_balloon(uint16_t hl, uint8_t row, uint8_t d, uint8_t e)
{
    uint16_t flyer, scr;
    uint8_t  a, b, c, old;

    HIT_ROW = row;                                         /* L177C-L177D */
    if (PLAYER != 0) hl = (uint16_t)(hl + K_P2_OFFSET);    /* L1780-L178A */
    b = 0x0C;                                              /* L178B */
    c = e;                                                 /* L178D: flyer X */
    for (;;) {
        if (cpu_rd(hl) & 0x80) {                           /* L178E-L1790 */
            e = cpu_rd((uint16_t)(hl + 1));                /* L1793-L1796: balloon X */
            a = (uint8_t)(e - c + 0x08);                   /* L1797-L1798 */
            if (a < 0x18) break;                           /* L179A-L179C */
        }
        hl = (uint16_t)(hl + 3);                           /* NextBalloon ($17EF) */
        if (--b == 0) {                                    /* L17F2-L17F3 */
            clear_contact();                               /* L17F6 */
            return;
        }
    }
    TMR_HIT_LOCKOUT = 0x03;                                /* L179F-L17A1 */
    cpu_wr(hl, 0x00);                                      /* L17A4: balloon gone */
    a = (uint8_t)((random8() & 0x07) + 1);                 /* L17A6-L17AB */
    flyer = rd16(A_FLYER_PTR);                             /* L17AC */
    cpu_wr(flyer, 0xA0);                                   /* L17AF */
    cpu_wr((uint16_t)(flyer + K_CL_FRAME), a);             /* L17B1-L17B2 */
    old = cpu_rd((uint16_t)(flyer + K_CL_YVEL));           /* L17B3-L17B6 */
    cpu_wr((uint16_t)(flyer + K_CL_YVEL), 0xFF);           /* L17B8 */
    if (old & 0x80)                                        /* L17B7, L17BA */
        cpu_wr((uint16_t)(flyer + K_CL_YVEL), REBOUND_SPEED);   /* L17BD-L17C0 */
    scr = screen_addr(d, e);                               /* L17C1 */
    a = 0x08;                                              /* L17C7 */
    do {
        cpu_wr(scr, 0); scr++;                             /* L17C9-L17CA */
        cpu_wr(scr, 0);                                    /* L17CB */
        scr = (uint16_t)(scr + 0x1F);                      /* L17C4, L17CC */
    } while (--a != 0);                                    /* L17CD-L17CE */
    CONTACT_ROW = 0;                                       /* L17D1 */
    if (GAME_ACTIVE == 0) return;                          /* L17D4-L17D8 */
    scr = (uint16_t)(R_PopTable + 2 * HIT_ROW);            /* L17D9-L17E1 */
    c = cpu_rd(scr);                                       /* L17E2: points / 10 */
    hw_sound(cpu_rd((uint16_t)(scr + 1)));                 /* L17E3-L17E5 */
    TMR_SOUND_OFF = 0x07;                                  /* L17E7-L17E9 */
    add_score(0x00, c);                                    /* L17EC */
}
