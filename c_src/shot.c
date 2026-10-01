/* shot.c - a screenshot of the game's bitmap as an 8-bit greyscale PNG.
 * The image data is a zlib stream of stored (uncompressed) blocks, so no
 * compression library is needed. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "shot.h"

#define W 256
#define H 224

static uint32_t crc_table[256];

static void crc_init(void)
{
    uint32_t n, c;
    int k;
    for (n = 0; n < 256; n++) {
        c = n;
        for (k = 0; k < 8; k++) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
        crc_table[n] = c;
    }
}

static uint32_t crc_update(uint32_t c, const uint8_t *p, size_t n)
{
    while (n--) c = crc_table[(c ^ *p++) & 0xFF] ^ (c >> 8);
    return c;
}

static void be32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16); p[2] = (uint8_t)(v >> 8); p[3] = (uint8_t)v;
}

static int chunk(FILE *f, const char *type, const uint8_t *data, uint32_t len)
{
    uint8_t  hdr[8], tail[4];
    uint32_t c;
    be32(hdr, len);
    memcpy(hdr + 4, type, 4);
    c = crc_update(0xFFFFFFFFu, hdr + 4, 4);
    if (len) c = crc_update(c, data, len);
    be32(tail, c ^ 0xFFFFFFFFu);
    if (fwrite(hdr, 1, 8, f) != 8) return 1;
    if (len && fwrite(data, 1, len, f) != len) return 1;
    return fwrite(tail, 1, 4, f) != 4;
}

int shot_write_png(const char *path, const uint8_t *bitmap, int scale)
{
    static const uint8_t sig[8] = { 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };
    uint8_t  ihdr[13];
    uint8_t *raw, *z, *p;
    size_t   w, h, rawlen, zlen, pos;
    uint32_t a = 1, b = 0;
    FILE    *f;
    int      x, y, rc;

    if (scale < 1) scale = 1;
    if (scale > 8) scale = 8;
    w = (size_t)W * scale;
    h = (size_t)H * scale;
    rawlen = h * (w + 1);
    raw = (uint8_t *)malloc(rawlen);
    zlen = 2 + rawlen + 5 * (rawlen / 65535 + 1) + 4;
    z = (uint8_t *)malloc(zlen);
    if (!raw || !z) { free(raw); free(z); return 1; }

    p = raw;
    for (y = 0; y < (int)h; y++) {
        const uint8_t *line = bitmap + 32 * (y / scale);
        *p++ = 0;                                          /* filter: none */
        for (x = 0; x < (int)w; x++) {
            int px = x / scale;
            *p++ = (line[px >> 3] >> (px & 7)) & 1 ? 0xFF : 0x00;
        }
    }
    for (pos = 0; pos < rawlen; pos++) {                   /* adler32 */
        a = (a + raw[pos]) % 65521u;
        b = (b + a) % 65521u;
    }
    p = z;
    *p++ = 0x78; *p++ = 0x01;                              /* zlib header */
    for (pos = 0; pos < rawlen; ) {                        /* stored blocks */
        size_t n = rawlen - pos;
        if (n > 65535) n = 65535;
        *p++ = (uint8_t)(pos + n == rawlen ? 1 : 0);
        *p++ = (uint8_t)n; *p++ = (uint8_t)(n >> 8);
        *p++ = (uint8_t)~n; *p++ = (uint8_t)(~n >> 8);
        memcpy(p, raw + pos, n);
        p += n;
        pos += n;
    }
    be32(p, (b << 16) | a);
    p += 4;

    crc_init();
    f = fopen(path, "wb");
    if (!f) { free(raw); free(z); return 1; }
    be32(ihdr, (uint32_t)w);
    be32(ihdr + 4, (uint32_t)h);
    ihdr[8] = 8; ihdr[9] = 0; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;   /* 8-bit grey */
    rc = fwrite(sig, 1, 8, f) != 8;
    rc |= chunk(f, "IHDR", ihdr, 13);
    rc |= chunk(f, "IDAT", z, (uint32_t)(p - z));
    rc |= chunk(f, "IEND", NULL, 0);
    rc |= fclose(f) != 0;
    free(raw);
    free(z);
    return rc;
}
