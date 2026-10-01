/* shot.h - write the game's bitmap as a PNG (uncompressed, no library). */
#ifndef SHOT_H
#define SHOT_H

#include <stdint.h>

/* bitmap: 224 lines of 32 bytes as plat_video_present gets it; scale 1-8.
 * Returns 0 on success. */
int shot_write_png(const char *path, const uint8_t *bitmap, int scale);

#endif /* SHOT_H */
