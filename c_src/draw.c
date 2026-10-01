/* draw.c - SECTION 3 ($0476-$0A40): seesaw erase, text, screen address, and
 * the erase / draw routines of the two clown objects.
 *
 * Sprites go through the MB14241 shifter exactly as in the ROM: shift_amt()
 * is OUT 1, shift_data() OUT 2, shift_in() IN 3 (state.h).  Pictures and the
 * font are read from the ROM image at their ROM addresses.
 */
#include "state.h"
#include "hw.h"
#include "game.h"

/* EraseSeesaw ($0476): blank the seesaw where it was last drawn and take its new X. */
void erase_seesaw(void)
{
    uint16_t hl;
    uint8_t  a, b, c;

    if (!(SEESAW_STATE & 0x80)) return;                    /* L0476-L047B */
    b = SEESAW_DRAWN_X;                                    /* L047C-L047D */
    a = PADDLE_POS;                                        /* L047E */
    if (a >= 0xD8) a = 0xD7;                               /* L0481-L0486 */
    SEESAW_X = a;                                          /* L0488 */
    SEESAW_DRAWN_X = a;                                    /* L048B */
    hl = (uint16_t)(0x3E00 | (((b >> 3) & 0x1F) | 0x60));  /* L048C-L0495: line 211 at the old X */
    c = 0x10;                                              /* L049D: seesaw and rider */
    if (cpu_rd(rd16(A_RIDER_PTR)) & 0x20) c = 0x08;        /* L0497-L04A3: the rider blanks itself */
    do {
        cpu_wr(hl, 0); hl++;                               /* L04A9-L04B2 */
        cpu_wr(hl, 0); hl++;
        cpu_wr(hl, 0); hl++;
        cpu_wr(hl, 0); hl++;
        cpu_wr(hl, 0); hl++;
        cpu_wr(hl, 0);                                     /* L04B3 */
        hl = (uint16_t)(hl + 0xFFDB);                      /* L04A6, L04B4: one line up */
    } while (--c != 0);                                    /* L04B5-L04B6 */
}

/* DrawString ($04BB): draw A characters from HL at screen address DE.
 * Both pointers are left after the last character; the ROM returns A = 0. */
void draw_string(uint8_t a, uint16_t *hlp, uint16_t *dep)
{
    uint16_t hl = *hlp, de = *dep;
    do {                                                   /* L04BB */
        uint16_t glyph, scr;
        uint8_t  ch, rows;
        for (;;) {
            ch = (uint8_t)(cpu_rd(hl) - 0x30);             /* L04BC-L04BE */
            hl++;                                          /* L04BD */
            if (!(ch & 0x80)) break;                       /* L04C0 JP L04D4 */
            {                                              /* a code below '0': skip columns */
                uint8_t b = ch;                            /* L04C3 */
                do {
                    de++;                                  /* L04C4 */
                    if ((de & 0x1F) == 0)                  /* L04C5-L04C8 */
                        de = (uint16_t)(de + 0x200);       /* L04CB-L04CC */
                    b++;                                   /* L04CD */
                } while (b != 0);                          /* L04CE */
            }                                              /* L04D1 */
        }
        glyph = glyph_addr(ch);                            /* L04D6: DE = glyph, HL = screen address */
        scr = (uint16_t)(de + 0x20);                       /* L04D9-L04DB: first row one line below */
        rows = 0x0A;                                       /* L04DC */
        do {
            cpu_wr(scr, cpu_rd(glyph));                    /* L04DF-L04E1 */
            glyph++;                                       /* L04E0 */
            scr = (uint16_t)(scr + 0x20);                  /* L04E2 */
        } while (--rows != 0);                             /* L04E4-L04E5 */
        de++;                                              /* L04EA */
    } while (--a != 0);                                    /* L04EC-L04ED */
    *hlp = hl;
    *dep = de;
}

/* TwoBitsWide ($0521): the low two bits of the row, each widened to 4 pixels. */
static uint8_t two_bits_wide(uint8_t bits)
{
    uint8_t c = 0, a = 0;
    if (bits & 0x01) c = 0x0F;                             /* L0521-L0527 */
    if (bits & 0x02) a = 0xF0;                             /* L0529-L0530 */
    return (uint8_t)(a | c);                               /* L0532 */
}

/* DrawBigString ($04F1): draw A characters from HL at DE, four times as wide
 * and on every other line. */
void draw_big_string(uint8_t a, uint16_t *hlp, uint16_t *dep)
{
    uint16_t hl = *hlp, de = *dep;
    do {                                                   /* L04F1 */
        uint16_t glyph, scr;
        uint8_t  ch, rows;
        ch = (uint8_t)(cpu_rd(hl) - 0x30);                 /* L04F2-L04F3 */
        hl++;                                              /* L04F5 */
        glyph = glyph_addr(ch);                            /* L04F7 */
        scr = de;
        rows = 0x0A;                                       /* L04FA */
        do {
            uint8_t  row = cpu_rd(glyph);                  /* L04FE */
            uint16_t p = scr;                              /* L04FC */
            int      k;
            glyph++;                                       /* L04FF */
            for (k = 0; k < 4; k++) {                      /* L0500-L0509 */
                cpu_wr(p, two_bits_wide(row));             /* L0533 */
                p++;                                       /* L0534 */
                row = (uint8_t)(row >> 2);
            }
            scr = (uint16_t)(scr + 0x40);                  /* L050D-L0510: two lines down */
        } while (--rows != 0);                             /* L0511-L0512 */
        de = (uint16_t)(scr + 0xFD84);                     /* L0515-L0519: back up, 4 bytes right */
    } while (--a != 0);                                    /* L051B-L051D */
    *hlp = hl;
    *dep = de;
}

/* ScreenAddr ($0537): video RAM address of pixel X = E, Y = D. */
uint16_t screen_addr(uint8_t d, uint8_t e)
{
    return (uint16_t)(((((uint16_t)d << 8) | e) >> 3) + 0x2400);   /* L0537-L0547 */
}

/* GlyphAddr ($0549): font glyph for character code A - '0'. */
uint16_t glyph_addr(uint8_t a)
{
    uint16_t hl = R_Font - 10;                             /* L0551 */
    a++;                                                   /* L0549 */
    if (!((uint8_t)(a - 0x0B) & 0x80))                     /* L054A-L054C JM L0551 */
        a = (uint8_t)(a - 0x06);                           /* L054F */
    do {
        hl = (uint16_t)(hl + 0x000A);                      /* L0554-L0557 */
    } while (--a != 0);                                    /* L0558-L0559 */
    return hl;                                             /* L055C XCHG */
}

/* BlankBox ($06B8): write zeros over the object's box and clear state b5. */
void blank_box(uint16_t hl)
{
    uint16_t scr;
    uint8_t  a, width;

    cpu_wr(hl, (uint8_t)(cpu_rd(hl) & 0xDF));              /* L06B8-L06B9, ObjectBox L070E */
    scr = rd16((uint16_t)(hl + K_CL_SCREEN));              /* L070F-L0715 */
    a = cpu_rd((uint16_t)(hl + K_CL_ROWS));                /* L0717, L06C2 */
    width = cpu_rd((uint16_t)(hl + K_CL_WIDTH));           /* L06BE */
    if (width == 2) {                                      /* L06C0-L06C3 */
        do {
            cpu_wr(scr, 0); scr++;                         /* L06C8-L06C9 */
            cpu_wr(scr, 0);                                /* L06CA */
            scr = (uint16_t)(scr + 0x1F);                  /* L06C6, L06CB */
        } while (--a != 0);                                /* L06CC-L06CD */
    } else {
        do {
            cpu_wr(scr, 0); scr++;                         /* L06D3-L06D4 */
            cpu_wr(scr, 0); scr++;                         /* L06D5-L06D6 */
            cpu_wr(scr, 0);                                /* L06D7 */
            scr = (uint16_t)(scr + 0x1E);                  /* L06D1, L06D8 */
        } while (--a != 0);                                /* L06D9-L06DA */
    }
}

/* EraseFlyer ($06B2) and RestoreBackground ($06DE): remove the object's last
 * picture, as its state bits ask. */
void erase_flyer(uint16_t hl)
{
    uint16_t scr, saved;
    uint8_t  c;

    if (cpu_rd(hl) & 0x20) {                               /* L06B2-L06B5 */
        blank_box(hl);
        return;
    }
    /* RestoreBackground ($06DE) */
    if (!(cpu_rd(hl) & 0x40)) return;                      /* L06DE-L06E1 */
    if (cpu_rd(hl) & 0x10) {                               /* L06E2-L06E5: slow object */
        cpu_wr(hl, (uint8_t)(cpu_rd(hl) + 1));             /* L06E8 */
        if (cpu_rd(hl) & 0x03) return;                     /* L06E9-L06EC */
        cpu_wr(hl, (uint8_t)(cpu_rd(hl) & 0xF8));          /* L06ED-L06F0 */
    }
    cpu_wr(hl, (uint8_t)(cpu_rd(hl) & 0xBF));              /* L06F1-L06F2, ObjectBox L070E */
    scr = rd16((uint16_t)(hl + K_CL_SCREEN));              /* L070F-L0715 */
    c = cpu_rd((uint16_t)(hl + K_CL_ROWS));                /* L0717 */
    saved = (uint16_t)(hl + K_CL_SAVED);                   /* L0718, L06F7 */
    do {
        cpu_wr(scr, cpu_rd(saved)); saved++; scr++;        /* L06F9-L06FC */
        cpu_wr(scr, cpu_rd(saved)); saved++; scr++;        /* L06FD-L0700 */
        cpu_wr(scr, cpu_rd(saved)); saved++;               /* L0701-L0703 */
        scr = (uint16_t)(scr + 0x1E);                      /* L0705-L0707 */
    } while (--c != 0);                                    /* L0709-L070A */
}

/* EraseRider ($071A): blank the rider's old box if its state asks for it. */
void erase_rider(uint16_t hl)
{
    if (cpu_rd(hl) & 0x20) blank_box(hl);                  /* L071A-L071E */
}

/* DrawFlyer ($0721): move the flying clown and draw it. */
void draw_flyer(uint16_t hl)
{
    uint16_t scr, pic, saved;
    uint8_t  a, c, d, e, rows;

    a = cpu_rd(hl);                                        /* L0721 */
    if (!(a & 0x80)) return;                               /* L0722-L0723 */
    if ((a & 0x10) && (cpu_rd(hl) & 0x03)) return;         /* L0724-L072C: slow object, not its tick */
    cpu_wr(hl, (uint8_t)(ERASE_MODE | cpu_rd(hl)));        /* L072D-L0731 */
    c = cpu_rd((uint16_t)(hl + K_CL_FRAME));               /* L0733 */
    a = cpu_rd((uint16_t)(hl + K_CL_XVEL));                /* L0735 */
    for (;;) {
        a = (uint8_t)(a + cpu_rd((uint16_t)(hl + K_CL_X)));/* L0736-L0737 */
        if (a < 0xF2) break;                               /* L0738-L073A */
        a = (uint8_t)(0 - cpu_rd((uint16_t)(hl + K_CL_XVEL)));   /* L073D-L0740: reverse */
        cpu_wr((uint16_t)(hl + K_CL_XVEL), a);             /* L0741 */
    }                                                      /* L0742 */
    cpu_wr((uint16_t)(hl + K_CL_X), a);                    /* L0745 */
    e = a;                                                 /* L0746 */
    shift_amt((uint8_t)(a & 0x07));                        /* L0747-L0749 */
    a = (uint8_t)(cpu_rd((uint16_t)(hl + K_CL_YVEL)) + cpu_rd((uint16_t)(hl + K_CL_Y)));   /* L074C-L074E */
    if (a >= 0xF0) {                                       /* L074F-L0751 */
        cpu_wr((uint16_t)(hl + K_CL_YVEL),
               (uint8_t)(0 - cpu_rd((uint16_t)(hl + K_CL_YVEL))));   /* L0754-L0758 */
        a = cpu_rd((uint16_t)(hl + K_CL_Y));               /* L0759-L075A */
    }
    cpu_wr((uint16_t)(hl + K_CL_Y), a);                    /* L075B */
    d = a;                                                 /* L075C */
    scr = screen_addr(d, e);                               /* L075E */
    wr16((uint16_t)(hl + K_CL_SCREEN), scr);               /* L0761-L0763 */
    pic = rd16((uint16_t)(R_ClownPictures + 2 * c));       /* L0766-L076D */
    rows = cpu_rd(pic); pic++;                             /* L076F-L0770 */
    cpu_wr((uint16_t)(hl + K_CL_ROWS), rows);              /* L0772 */
    cpu_wr((uint16_t)(hl + K_CL_WIDTH), (uint8_t)(cpu_rd(pic) + 1));   /* L0774-L0777 */
    pic++;                                                 /* L0775 */
    saved = (uint16_t)(hl + K_CL_SAVED);                   /* L0778-L0779 */
    do {
        cpu_wr(saved, cpu_rd(scr)); saved++;               /* L077C-L077E */
        shift_data(cpu_rd(pic)); pic++;                    /* L077F-L0781 */
        cpu_wr(scr, (uint8_t)(shift_in() | cpu_rd(scr)));  /* L0783-L0786 */
        scr++;                                             /* L0787 */
        cpu_wr(saved, cpu_rd(scr)); saved++;               /* L0788-L078A */
        shift_data(cpu_rd(pic)); pic++;                    /* L078B-L078D */
        cpu_wr(scr, (uint8_t)(shift_in() | cpu_rd(scr)));  /* L078F-L0792 */
        scr++;                                             /* L0793 */
        cpu_wr(saved, cpu_rd(scr)); saved++;               /* L0794-L0796 */
        shift_data(0);                                     /* L0797-L0798 */
        cpu_wr(scr, (uint8_t)(shift_in() | cpu_rd(scr)));  /* L079A-L079D */
        scr = (uint16_t)(scr + 0x001E);                    /* L079F-L07A2 */
    } while (--rows != 0);                                 /* L07A5-L07A6 */
}

/* DrawRider ($07AA): draw the clown that stands on the seesaw. */
void draw_rider(uint16_t hl)
{
    uint16_t scr, pic, saved;
    uint8_t  a, d, e, rows;

    if (!(cpu_rd(hl) & 0x80)) return;                      /* L07AA-L07AC */
    d = 0x22;                                              /* L07B5 */
    if (parity_even((uint8_t)(SEESAW_STATE & 0x60))) d = 0x00;   /* L07B0-L07BA JPO */
    e = (uint8_t)(SEESAW_X + d);                           /* L07BC-L07C0 */
    shift_amt((uint8_t)(e & 0x07));                        /* L07C1-L07C3 */
    cpu_wr((uint16_t)(hl + K_CL_X), e);                    /* L07C5 */
    a = (uint8_t)(cpu_rd((uint16_t)(hl + K_CL_YVEL)) + cpu_rd((uint16_t)(hl + K_CL_Y)));   /* L07C7-L07C9 */
    d = a;                                                 /* L07CA */
    cpu_wr((uint16_t)(hl + K_CL_Y), a);                    /* L07CB */
    scr = screen_addr(d, e);                               /* L07CD */
    wr16((uint16_t)(hl + K_CL_SCREEN), scr);               /* L07D0-L07D2 */
    rows = 0x0F;                                           /* L07D4 */
    cpu_wr((uint16_t)(hl + K_CL_ROWS), rows);              /* L07D6 */
    cpu_wr((uint16_t)(hl + K_CL_WIDTH), 0x02);             /* L07D8 */
    saved = (uint16_t)(hl + K_CL_SAVED);                   /* L07DA-L07DB */
    pic = R_RiderPicture;                                  /* L07DC */
    do {
        cpu_wr(saved, cpu_rd(scr)); saved++;               /* L07E0-L07E2 */
        shift_data(cpu_rd(pic)); pic++;                    /* L07E3-L07E5 */
        cpu_wr(scr, (uint8_t)(shift_in() | cpu_rd(scr)));  /* L07E7-L07EA */
        scr++;                                             /* L07EB */
        cpu_wr(saved, cpu_rd(scr)); saved++;               /* L07EC-L07EE */
        shift_data(0);                                     /* L07EF-L07F0 */
        cpu_wr(scr, (uint8_t)(shift_in() | cpu_rd(scr)));  /* L07F2-L07F5 */
        scr = (uint16_t)(scr + 0x001F);                    /* L07F7-L07FA */
    } while (--rows != 0);                                 /* L07FD-L07FE */
}
