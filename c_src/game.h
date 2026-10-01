/* game.h - prototypes of every translated routine of the Clowns program ROM.
 *
 * One C function per routine header of ../disasm/clowns_program_rom.asm, named
 * after its label in snake_case, with its ROM address.  8080 registers that a
 * routine takes or returns are parameters and return values; a routine that
 * the ROM enters by falling through is called at that point.
 */
#ifndef GAME_H
#define GAME_H

#include <stdint.h>

/* ---- boot.c: SECTION 1, $0000-$0137 --------------------------------------- */
void    reset(void);                  /* Reset ($0000) + Boot ($0018): sets g.cpu_loop */
void    self_test_pass(void);         /* RamTest ($0022), RamError ($00C1), RomTest ($00E5) */
void    self_test_wait_pass(void);    /* SelfTestWait ($011F) */

/* ---- irq.c: SECTION 2, $0138-$0475 ---------------------------------------- */
void    rst1(void);                   /* Rst1 ($0008) -> Rst1Handler ($0138) */
void    rst2(void);                   /* Rst2 ($0010) -> Rst2Handler ($0175) */
void    update_flyer(void);           /* UpdateFlyer ($014C) */
void    frame_task(void);             /* FrameTask ($0198), FrameTimers ($01DE) */
void    tick_second_timer(void);      /* TickSecondTimer ($01ED) */
void    tick_timers(void);            /* TickTimers ($0205) */
uint8_t tick_timer_list(uint16_t hl, uint8_t c, uint8_t b);  /* TickTimerList ($0223): returns B */
void    play_tune(void);              /* PlayTune ($0237) */
void    draw_seesaw(void);            /* DrawSeesaw ($02FB) */
void    coin_switch(void);            /* CoinSwitch ($041F) */
void    check_contact(void);          /* CheckContact ($043F) */

/* ---- draw.c: SECTION 3, $0476-$0A40 --------------------------------------- */
void     erase_seesaw(void);          /* EraseSeesaw ($0476) */
void     draw_string(uint8_t a, uint16_t *hl, uint16_t *de);      /* DrawString ($04BB): returns A = 0 */
void     draw_big_string(uint8_t a, uint16_t *hl, uint16_t *de);  /* DrawBigString ($04F1) */
uint16_t screen_addr(uint8_t d, uint8_t e);                       /* ScreenAddr ($0537): returns DE */
uint16_t glyph_addr(uint8_t a);                                   /* GlyphAddr ($0549): returns DE */
void     erase_flyer(uint16_t hl);    /* EraseFlyer ($06B2), RestoreBackground ($06DE) */
void     blank_box(uint16_t hl);      /* BlankBox ($06B8) */
void     erase_rider(uint16_t hl);    /* EraseRider ($071A) */
void     draw_flyer(uint16_t hl);     /* DrawFlyer ($0721) */
void     draw_rider(uint16_t hl);     /* DrawRider ($07AA) */

/* ---- mainloop.c: SECTION 4, $0A41-$0DF3 ----------------------------------- */
void     game_start(void);            /* GameStart ($0A41) */
void     main_loop_pass(void);        /* MainLoop ($0A51): one pass */
uint8_t  random8(void);               /* Random ($0AA5) */
void     animate_flyer(void);         /* AnimateFlyer ($0AD7) */
void     move_balloons_right(uint16_t de);   /* MoveBalloonsRight ($0B17) */
void     move_balloons_left(uint16_t de);    /* MoveBalloonsLeft ($0B42) */
uint16_t player_row(uint16_t de);     /* PlayerRow ($0B6D): returns HL */
void     draw_balloon(uint16_t de, uint16_t hl);   /* DrawBalloon ($0B78) */
void     serve_clown(void);           /* ServeClown ($0BA4) */
void     format_scores(void);         /* FormatScores ($0C0D), falls into draw_next_digit */
void     draw_next_digit(void);       /* DrawNextDigit ($0C25) */
void     format_score(uint16_t *bc, uint16_t *hl);  /* FormatScore ($0C62) */
uint8_t  nibble_to_char(uint8_t a);   /* NibbleToChar ($0C77) */
void     read_start_buttons(void);    /* ReadStartButtons ($0CA0) */
void     draw_playfield_if_on(void);  /* DrawPlayfieldIfOn ($0CB5) */
void     draw_playfield(void);        /* DrawPlayfield ($0CBA) */
void     autopilot(void);             /* Autopilot ($0CE5) */
void     check_rows_cleared(void);    /* CheckRowsCleared ($0D16) */

/* ---- events.c: SECTION 6, $117B-$1348 ------------------------------------- */
void     check_timeout(void);         /* CheckTimeout ($117B) */
void     script_timeout(void);        /* ScriptTimeout ($118A) */
void     run_timer_events(void);      /* RunTimerEvents ($1196) */
void     splat_step(void);            /* SplatStep ($11CA) */
void     splat_done(void);            /* SplatDone ($11DC), NextTurn ($1213) */
void     game_over(void);             /* GameOver ($1219) */
void     check_high_score(uint16_t de, uint16_t hl);  /* CheckHighScore ($1237) */
void     demo_over(void);             /* DemoOver ($124D) */
void     gravity_tick(void);          /* GravityTick ($1256) */
void     serve_jump(void);            /* ServeJump ($1277) */
void     walk_step(void);             /* WalkStep ($128F) */
void     script_timer_done(void);     /* ScriptTimerDone ($12B3) */
void     sound_off(void);             /* SoundOff ($12C0) */
void     run_timer_events2(void);     /* RunTimerEvents2 ($12C5) */
void     refill_rows(void);           /* RefillRows ($12DB) */
void     end_freeze(void);            /* EndFreeze ($130D) */
void     coin_counter_off(void);      /* CoinCounterOff ($1340) */

/* ---- switchtest.c: SECTION 7, $1349-$1412 --------------------------------- */
void     switch_test(void);           /* SwitchTest ($1349): entry, sets g.cpu_loop */
void     switch_test_pass(void);      /* SwitchTest's loop ($134D-$13B0) */
void     clear_ram_top(uint8_t a);    /* ClearRamTop ($13E7) */

/* ---- script.c: SECTION 8, $1413-$1525 ------------------------------------- */
void     script_command(uint8_t op, uint16_t de);   /* dispatch through ScriptOps ($1413) */
uint16_t fill_balloon_row(uint16_t hl, uint8_t b);  /* FillBalloonRow ($14EE): returns HL */

/* ---- contact.c: SECTION 9, $1526-$17FF ------------------------------------ */
void     handle_contact(void);        /* HandleContact ($1526) */
void     splat(uint8_t e);            /* Splat ($1540): E = flyer X */
void     add_score(uint8_t b, uint8_t c);   /* AddScore ($1685) */
void     clear_contact(void);         /* ClearContact ($1777) */

#endif /* GAME_H */
