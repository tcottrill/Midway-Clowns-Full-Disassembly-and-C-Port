/* sound.c - the Clowns sound board, as a synthesizer (see sound.h).
 *
 * Tone generator (ports 5 and 6), after MAME's mw8080bw_a.cpp: a 12-bit
 * counter preset = 64 x high + 2 x low counts up at 998.4 kHz (19.968 MHz /
 * 10 / 2) and toggles the output when it overflows, so the tone is
 * 998400 / (4096 - preset) / 2 Hz.  Bit 0 of port 5 gates it through a VCA.
 *
 * Port 7: b0 / b1 / b2 trigger the bottom / middle / top balloon pop (a noise
 * burst through a VCA and filters on the board), b3 enables the sound output,
 * b4 triggers the springboard hit (an op-amp oscillator burst), b5's rising
 * edge plays the miss sound.  Those four are approximated here: envelopes and
 * pitches chosen by ear, not derived from the schematic.
 */
#include <math.h>
#include <string.h>
#include "sound.h"

#define TONE_CLOCK 998400.0

static struct {
    int      rate;
    double   volume;
    /* tone generator */
    uint8_t  lo, hi;
    double   tone_phase;        /* 0..1 */
    double   tone_gain;         /* VCA, 0..1 */
    /* port 7 */
    uint8_t  port;
    double   master;            /* b3 enable, smoothed */
    /* pops: one noise voice per row */
    double   pop_env[3];
    double   pop_lp[3];
    uint32_t lfsr;
    double   noise_phase, noise_val;
    /* springboard hit */
    double   hit_env, hit_phase;
    /* miss */
    double   miss_t;            /* seconds since trigger, < 0 = idle */
    double   miss_phase;
} s;

void sound_reset(int sample_rate)
{
    double vol = s.volume;
    memset(&s, 0, sizeof s);
    s.rate = sample_rate > 0 ? sample_rate : 44100;
    s.volume = vol > 0.0 ? vol : 0.6;
    s.lfsr = 0x1FFFF;
    s.miss_t = -1.0;
}

void sound_set_volume(int percent)
{
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;
    s.volume = percent / 100.0;
}

void sound_tone_lo(uint8_t v) { s.lo = v; }
void sound_tone_hi(uint8_t v) { s.hi = v; }

void sound_port(uint8_t v)
{
    uint8_t rising = (uint8_t)(v & ~s.port);
    int i;
    s.port = v;
    for (i = 0; i < 3; i++)
        if (rising & (1 << i)) s.pop_env[i] = 1.0;
    if (rising & 0x10) { s.hit_env = 1.0; s.hit_phase = 0.0; }
    if (rising & 0x20) { s.miss_t = 0.0; s.miss_phase = 0.0; }
}

static double noise_step(void)
{
    /* 17-bit LFSR sampled at 7.7 kHz (the board's noise clock per MAME) */
    s.noise_phase += 7700.0 / s.rate;
    while (s.noise_phase >= 1.0) {
        uint32_t bit = ((s.lfsr >> 0) ^ (s.lfsr >> 3)) & 1u;
        s.lfsr = (s.lfsr >> 1) | (bit << 16);
        s.noise_val = (s.lfsr & 1u) ? 1.0 : -1.0;
        s.noise_phase -= 1.0;
    }
    return s.noise_val;
}

void sound_render(int16_t *out, int frames)
{
    /* pop voices: bottom, middle, top - decay time and brightness differ */
    static const double pop_tau[3]  = { 0.110, 0.075, 0.045 };
    static const double pop_cut[3]  = { 0.10, 0.22, 0.45 };
    static const double pop_gain[3] = { 0.55, 0.50, 0.45 };
    const double dt = 1.0 / s.rate;
    int n, i;

    for (n = 0; n < frames; n++) {
        double mix = 0.0, target, noise;
        int    preset = ((s.hi & 0x3F) << 6) | (((s.lo >> 1) & 0x1F) << 1);
        double freq = TONE_CLOCK / (4096 - preset) / 2.0;

        /* tone generator through its VCA */
        target = (s.lo & 1) ? 1.0 : 0.0;
        s.tone_gain += (target - s.tone_gain) * (target > s.tone_gain ? 0.02 : 0.004);
        s.tone_phase += freq * dt;
        if (s.tone_phase >= 1.0) s.tone_phase -= floor(s.tone_phase);
        mix += (s.tone_phase < 0.5 ? 0.30 : -0.30) * s.tone_gain;

        /* balloon pops */
        noise = noise_step();
        for (i = 0; i < 3; i++) {
            if (s.pop_env[i] > 0.0005) {
                s.pop_lp[i] += (noise - s.pop_lp[i]) * pop_cut[i];
                mix += s.pop_lp[i] * s.pop_env[i] * pop_gain[i];
                s.pop_env[i] *= exp(-dt / pop_tau[i]);
            }
        }

        /* springboard hit: a low damped tone */
        if (s.hit_env > 0.0005) {
            s.hit_phase += 140.0 * dt;
            mix += sin(s.hit_phase * 6.283185307179586) * s.hit_env * 0.55;
            s.hit_env *= exp(-dt / 0.070);
        }

        /* miss: a falling tone, then a thud */
        if (s.miss_t >= 0.0) {
            if (s.miss_t < 0.35) {
                double f = 700.0 - 1700.0 * s.miss_t;
                s.miss_phase += f * dt;
                if (s.miss_phase >= 1.0) s.miss_phase -= floor(s.miss_phase);
                mix += (s.miss_phase < 0.5 ? 0.22 : -0.22);
            } else if (s.miss_t < 0.50) {
                mix += noise * 0.35 * (1.0 - (s.miss_t - 0.35) / 0.15);
            } else {
                s.miss_t = -1.0 - dt;
            }
            if (s.miss_t >= 0.0) s.miss_t += dt;
        }

        /* b3: sound enable */
        target = (s.port & 0x08) ? 1.0 : 0.0;
        s.master += (target - s.master) * 0.01;
        mix *= s.master * s.volume;

        if (mix > 1.0) mix = 1.0;
        if (mix < -1.0) mix = -1.0;
        out[n] = (int16_t)(mix * 30000.0);
    }
}
