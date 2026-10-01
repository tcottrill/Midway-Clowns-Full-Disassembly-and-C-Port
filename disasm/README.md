# Clowns (Midway, 1978) - annotated disassembly

Byte-exact, fully labelled listing of the Clowns program ROM (MAME `clowns`, rev. 2:
six 1K ROMs, `$0000-$17FF`), generated from the ROM image and checked against it by
a read-back verifier. The layout follows the
[Tempest disassembly](https://github.com/tcottrill/Tempest-Full-Disassembly-and-C-Port):
one program listing, one defines file, generator scripts, a verifier.

[`sprites_preview.html`](sprites_preview.html) draws every bitmap in the ROM (font,
seesaw, clowns, balloons). The C port built from this listing, and the test that
runs it against the real ROM, are in [`../c_src/`](../c_src/README.md).

## Regenerate and verify

```
cd disasm
python gen_from_roms.py                    # ROMs from ../roms
python gen_from_roms.py C:\path\to\clowns.zip
```

`gen_from_roms.py` finds the six ROMs by size and CRC32 (zip or loose files, any
names), writes `build/clowns_cpu.bin`, then runs:

1. `emit.py` -> `clowns_program_rom.asm`
2. `emit_defines.py` -> `clowns_defines.asm`
3. `verify.py` - must print `MISMATCHES : 0`
4. `emit_sprites.py` -> `sprites_preview.html`

Any failing step prints `!!` and the exit status is 1. Python 3 only, no packages.

Current result: verify 6144/6144 bytes, 0 mismatches; 2238 instructions, 2311 data
bytes, 207 named labels, 137 routine headers.

## Files

| File | What |
|---|---|
| `clowns_program_rom.asm` | program ROM `$0000-$17FF` - generated |
| `clowns_defines.asm` | memory map, I/O ports, RAM variables, constants - generated |
| `sprites_preview.html` | rendered bitmaps - generated |
| `gen_from_roms.py` | driver (above) |
| `i8080.py` | Intel 8080 opcode table, decoder and encoder |
| `trace.py` | recursive-descent tracer: separates code from data |
| `notes.py` | data layout, RAM / port / constant tables, loader for `notes/*.txt` |
| `notes/*.txt` | labels, routine headers and comments, by address |
| `emit.py`, `emit_defines.py`, `emit_sprites.py` | generators |
| `verify.py` | independent read-back of the two .asm files: re-encodes every line and compares with the image |

The `.asm` files are generated: change `notes.py` / `notes/*.txt` and regenerate.

Inputs, not distributed here: the ROM set (`../roms/clowns.zip`). No source code for
Clowns is known. Hardware facts (memory map, ports, switch bits, video layout,
interrupts) follow the MAME driver `mw8080bw.cpp` / `mw8080bw_a.cpp`.

The reading of the code in the listing is not only the author's: the C port in
`../c_src` is a statement-by-statement translation of it, and that port matches the
real ROM byte for byte over 1.2 million compared events (96 % of the instructions).

## Conventions (program listing)

- Intel 8080 mnemonics. Directives as the Tempest / Space Duel listings: `.org`,
  `.include`, `.alias NAME $VALUE`, `.byte`, `.word`; `$` hex; `<` / `>` low / high
  byte; `[ ]` groups an expression.
- Every code and data line starts with its address label `Lxxxx:`. Named labels sit
  on their own line above it. Branch targets without a name are `Lxxxx`.
- Names were all given for this disassembly: routines and tables `CamelCase`, RAM
  and constants `UPPER_CASE`, script labels `Scr...`, script command handlers
  `Op...`, text `Txt...`.
- Operands are symbolic where the value is an address: jump / call targets, RAM
  variables (`STA FREEZE`, `LXI H,TEXT_BUF`, `P1_ROW_TOP+3`), ROM tables
  (`LXI H,NoteTable`, `LXI H,Font-10`), port numbers (`IN INP_DIP`,
  `OUT OUT_SOUND`), clown object offsets (`LXI B,CL_Y`). Counts, coordinates,
  screen addresses and other immediates are hex.
- Routine headers (a `;----` block): `; Name - description`, then details.
  Section banners (`;====`) split the ROM into nine parts.
- Data is laid out by what it is: bitmaps one row per line with the picture as the
  comment (bit 0 is the leftmost pixel); pointer tables as `.word` with names; text
  with the string as it appears on screen; the game script one command per line
  with the decoded command as the comment (`;SET GAME_ACTIVE = $01`,
  `;TEXT "GET READY" at col 11, line 112`); tunes one note per line.
- Comment-only lines (`;`) above a statement mark the parts of a long routine.

## Conventions (defines)

Sections: `Memory map`, `Input ports`, `Output ports` (the 8080's separate port
space), four `Work RAM` groups, `Constants`. Format `.alias NAME $VALUE ;comment`.
Every identifier the program listing uses is defined here.

## How the program works (short)

- **Boot** (`Boot`): DIP b7 on runs the RAM and ROM tests in a loop (`RamTest`,
  `RomTest`; the coin switch during the RAM test enters `SwitchTest`); off starts
  the game (`GameStart`).
- **Main loop** (`MainLoop`): a script interpreter. The script at `$0DF4` sequences
  attract mode, coin handling, game start and every jump with 17 commands
  (`ScriptOps`). When the script is on a `WAIT` the main loop runs the game tasks:
  contact handling, timer events, serve, picture selection, score line, row bonus.
- **Interrupts** (`Rst1Handler` mid-screen, `Rst2Handler` vblank): all drawing of
  moving objects. Each frame one interrupt updates the flying clown (`EraseFlyer`,
  `DrawFlyer`, `CheckContact`) and the other does the frame task: seesaw and rider
  on even frames, one balloon pass plus timers and coin switch on odd frames. They
  swap roles depending on the flyer's height so it is never redrawn under the beam.
- **Objects**: two clown objects (`CLOWN_A`, `CLOWN_B`) swap the roles of flyer and
  rider at every launch; three rows of 12 balloons per player; the seesaw.
- **Contact**: `DrawFlyer` saves the screen bytes under the clown; `CheckContact`
  reports the first row that was not empty; `HandleContact` decides from the
  position whether that was the floor (`Splat`), the seesaw (`LandOnSeesaw`), a
  ledge (`LedgeBounce`) or a balloon (`PopBalloon`).
- **Timers**: twelve down-counters ticked at 30 Hz or 1 Hz in the interrupt; expiry
  bits are picked up by `RunTimerEvents` / `RunTimerEvents2` / `CheckTimeout`.
- **Sound**: `PlayTune` drives the tone generator from `NoteTable`; pops, hit and
  miss are bits of `OUT_SOUND`.
