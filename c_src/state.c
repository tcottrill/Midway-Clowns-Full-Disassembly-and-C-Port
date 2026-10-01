/* state.c - the machine state and the computed-address accessors.
 *
 * The board decodes 15 address bits (MAME mw8080bw main_map): A13 = 0 is ROM
 * space ($0000-$1FFF and $4000-$5FFF, writes ignored), A13 = 1 is RAM
 * ($2000-$3FFF, seen again at $6000-$7FFF); A15 is not decoded.  Clowns has
 * ROM only at $0000-$17FF.  An empty ROM address reads as 0 here; on the board
 * nothing drives the bus there.  The game does reach $4000 and above: a
 * splatted clown sinks below the last screen line, and the rows of its picture
 * that fall past $3FFF are written into that empty space and lost.
 */
#include "state.h"

machine_state g;

uint8_t cpu_rd(uint16_t addr)
{
    addr &= 0x7FFF;
    if (addr & 0x2000) return g.ram[addr & 0x1FFF];
    return addr < PROGROM_SIZE ? progrom[addr] : 0;
}

void cpu_wr(uint16_t addr, uint8_t v)
{
    addr &= 0x7FFF;
    if (addr & 0x2000) {
        g.ram[addr & 0x1FFF] = v;
        return;
    }
    g.stray_writes++;                                      /* ROM space: nothing happens */
    g.stray_addr = addr;
}
