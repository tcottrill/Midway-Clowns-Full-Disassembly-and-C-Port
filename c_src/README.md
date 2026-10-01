# Clowns - C port

A C11 translation of the game program in
[`../disasm/clowns_program_rom.asm`](../disasm/clowns_program_rom.asm)
(Midway Clowns, 1978, MAME `clowns` rev. 2).

**Every routine of the ROM is translated, and it plays in a window with sound and
the paddle.** One C function per routine header of the listing, each with its ROM
address and an `Lxxxx` comment per statement: the reset path and the RAM / ROM self
test, the two interrupts, the script interpreter and its 17 commands, the game
tasks, the switch test. It is not an emulator: there is no 8080 core at runtime.

The display is the real one. The translated code writes the same bytes into a
modelled video RAM (`$2400-$3FFF`) through the same MB14241 shifter operations as
the ROM, and the backend shows that bitmap. ROM tables - pictures, font, script,
text, tunes - are read from the ROM image at their ROM addresses, never retyped.

How the listing and its names were made is in [`../disasm/`](../disasm/).

## Building and running

```bat
build_win.bat
clowns_win.exe
```

Needs Visual Studio 2022 (the scripts call its developer command prompt) and
nothing else. `build_win.bat` builds `clowns_win.exe` into `c_src` (objects in
`obj\win\`) and prints `WIN BUILD OK`; everything compiles at `/W4 /std:c11`
warning-free.

`progrom.c`, `rom_labels.h` and `state_defs.h` are generated. To regenerate them
from a ROM set:

```bat
python ..\disasm\gen_from_roms.py
python tools\gen_state.py
python tools\gen_roms.py
```

### Controls

| action | keys |
|---|---|
| paddle (the seesaw) | mouse X across the window; Left / Right arrows |
| coin | 5 |
| start, one / two players | 1 / 2 |
| self-test switch | **F2**, a latched toggle like the board's DIP switch 8. The ROM reads it at reset: F2 then F3 gives the RAM / ROM test, which repeats (10.6 s a pass, blank screen when all is well) until the switch is off |
| reset (power cycle) | **F3** |
| switch test | hold **5** at reset with the self-test switch on: COIN / PLAYER 1 / PLAYER 2 ON-OFF, the seesaw follows the paddle, 1 / 2 pick whose paddle |
| quit | Esc |

Both players use the same paddle.

### `clowns_win.ini`

Beside the exe; read at start and written back with the values that took effect.

| section | keys |
|---|---|
| `[dips]` | `coinage` 0 = 1 coin 1 player (second coin: 2 players), 1 = 1 coin 1 or 2 players, 2 = 2 coins 1 or 2 players, 3 = 2 coins per player; `bonus_game` 0 none, 1 / 2 / 3 = at 9000 / 11000 / 13000; `balloon_resets` 0 each row, 1 all rows; `extra_jump` 0 at 3000, 1 at 4000; `jumps` 0 = 3, 1 = 4 |
| `[main]` | `scale` window scale 1-6; `self_test` the switch at power-on |
| `[input]` | `mouse` 1 = mouse X moves the paddle; `key_speed` paddle counts per frame for the arrow keys |
| `[sound]` | `volume` 0-100 |

### Command line (`clowns_win.exe`)

| option | |
|---|---|
| `--test` | self-test switch on at power-on |
| `--scale N` | window scale |
| `--hidden` | never show the window (scripts) |
| `--quit-after-frames N` | timed run |

## Pacing

The board: CPU at 1.9968 MHz, 262 lines of 128 CPU cycles, 59.54 frames a second,
an interrupt at line 224 (vblank, `RST 2`) and at line 96 (`RST 1`). The ROM's main
loop has no frame wait - it spins as fast as the 8080 allows and everything timed
runs off the interrupts.

`app_loop.c` keeps one timeline in CPU cycles. The two interrupts sit on their exact
times; in between, main-loop passes are run, each charged the cycles the ROM spends
on it. Those costs are means measured on the real ROM (`tests\lockstep.exe --costs`):
a pass of the game tasks is about 800 cycles on the title screen, 2100 with the demo
running and 9000 in a game; the flyer's interrupt about 8000, the frame task 8300
(seesaw and rider) or 5000 (balloons and timers); `CLEAR` 192 per 32 bytes, text 1320
a character, big text 5950. While the ROM has interrupts disabled (it runs its script
commands that way) a raised interrupt waits and a second one is lost, as on the board.

Compared with the ROM running free on the 8080 core (`tests\lockstep.exe --free`,
interrupts on cycle times, 6000 frames of a coined game):

| | ROM | port |
|---|---|---|
| main-loop passes per frame, attract | 36.6 | 35.8 |
| interrupts taken | 11968 | 11971 |
| interrupts lost behind a DI | 32 | 29 |

## Verification

**`tests\lockstep.exe`** runs the real ROM (compiled in from `progrom.c`) on an 8080
interpreter - AAE's `cpu_i8080`, copied unchanged into `tests\i8080\` - with the
board around it: RAM, the shifter, the ports. Both machines are driven through the
same events - per frame the vblank interrupt, main-loop passes, the mid-screen
interrupt, main-loop passes - and after **every** event they are compared: all RAM
except the stack page (`$2300-$23FF`, which the port does not model), video RAM
included; the interrupt enable; the shifter; which loop the CPU is in; and the exact
sequence of port writes the event made. Inputs are scripted and the same for both.

```bat
build_all.bat
run_tests.bat
```

`build_all.bat` prints `ALL BUILDS OK`; `run_tests.bat` runs the 16 scenarios below
and ends `TESTS OK`. Every run ends `LOCKSTEP: PASS`:

| scenario | frames | events compared | of which interrupts | final scores |
|---|---|---|---|---|
| attract | 1500 | 15,287 | 2,999 | |
| one player, seesaw steered | 12000 | 120,168 | 23,999 | 14040 |
| one player, paddle held: three splats, game over | 6000 | 61,674 | 11,999 | 0 |
| one player, steered then left alone: game over, high score | 9000 | 91,741 | 17,999 | 2580, high 2580 |
| two players, turns change, game over | 14000 | 142,213 | 27,999 | 1200 / 3010, high 3010 |
| all rows, bonus game at 9000, 4 jumps, extra jump at 4000 | 20000 | 200,168 | 39,999 | 24700 |
| bonus game at 11000 | 16000 | 160,168 | 31,999 | 19290 |
| coinage 2: two coins | 5000 | 50,526 | 9,999 | 1460 |
| coinage 3: four coins, two players | 6000 | 60,732 | 11,999 | 1220 |
| coinage 3: three coins, one player | 4000 | 40,363 | 7,999 | 1280 |
| coinage 0: second coin, two players | 5000 | 50,594 | 9,999 | 730 |
| self test, looping (4 complete RAM + ROM tests) | 4 | 9 | 0 | |
| self test, switch turned off: into the game | 1200 | 12,139 | 2,392 | |
| switch test | 300 | 1,199 | 598 | |
| one player, 1 pass per interrupt period | 6000 | 24,168 | 11,999 | 5700 |
| one player, 12 passes per interrupt period | 6000 | 156,168 | 11,999 | 5700 |

A 40000-frame attract run (415,981 events) passes as well.

`run_tests.bat` ends with the coverage of those runs (`tools\coverage.py`): the ROM
executed **2148 of its 2238 instructions (96.0 %)** and entered **106 of 109
routines**, so that much of the translation is verified byte for byte. Not reached:

- `RamError`, `SelfTestWait` and the error branches of `RamTest` / `RomTest`: they
  need bad RAM or a bad ROM;
- `DemoOver` (three stores): the attract autopilot never missed;
- the skip codes of `DrawString`: no text in the ROM uses them;
- one instruction each in `EraseSeesaw` (`$04A3`) and `Splat` (`$157F`), which the
  listing shows cannot be reached.

What lockstep does not cover: interrupts that land in the middle of a main-loop
pass. It delivers them between passes, on both machines, which is one of the
interleavings the real machine can produce; the last two rows show the result does
not depend on how many passes run between interrupts.

**`tests\clowns_headless.exe`** is the whole port (the seam, the pacing, the sound
renderer) on a backend without a window: scripted coins, buttons and paddle, PNG
shots, a RAM checksum. The pictures in `shots\` are from it.

```bat
tests\clowns_headless.exe --frames 5200 --coin 950 --start1 1010 --track --shot 2500 shots\game_2500.png
```

## What lockstep found

Running the ROM against the port changed two things that reading the code had got
wrong or missed:

- **The memory map.** The first version of both the port and the oracle had RAM
  mirrored at `$4000`. A splatted clown keeps sinking one line per update, and once
  it is below line 223 its picture is drawn at `$4000` and up - which, with that
  mirror, scribbled over the timers at `$2028` and froze a two-player game. The
  board decodes ROM space there (MAME `mw8080bw` `main_map`: 15 address bits, A13 =
  0 is ROM, writes ignored), so on the real machine those rows are simply lost.
  `state.c` and the oracle now decode addresses the way the board does.
- **Null clown pointers.** After a `CLEAR` and before the first serve the clown
  pointers are 0. The ROM then reads ROM bytes as an object (state 0 = not in use)
  and, when the gravity timer is still running from the previous turn, increments
  "YVEL" at `$0004` - a write into ROM that does nothing. The port reaches objects
  through `cpu_rd` / `cpu_wr` for that reason, and lockstep checks that both sides
  make the same number of such writes.

## What is here

| file | |
|---|---|
| `state.h`, `state.c` | the machine state `machine_state g`: `ram[0x2000]` (`$2000-$3FFF`), the shifter, the interrupt enable, which loop the CPU is in; `cpu_rd` / `cpu_wr` with the board's address decoding |
| `state_defs.h` | **generated** (`tools\gen_state.py` from `../disasm/clowns_defines.asm`): every named cell as `A_NAME` address + `NAME` lvalue, `K_NAME` constants, `P_NAME` ports |
| `rom_labels.h`, `progrom.c/.h` | **generated** (`tools\gen_roms.py`): the ROM image and `R_Name` for every named label of the listing |
| `hw.h` | the hardware seam the game code calls: the three input ports, `OUT_MISC`, watchdog, tone generator, sound port |
| `game.h` | prototypes of every translated routine |
| `boot.c` `irq.c` `draw.c` `mainloop.c` `events.c` `switchtest.c` `script.c` `contact.c` | the game, one file per section of the listing (1, 2, 3, 4, 6, 7, 8, 9; section 5 is the script and text, data read from the ROM image) |
| `app_loop.c` | the native seam over the platform: cycle timeline, interrupts, pass costs, inputs to ports, watchdog |
| `sound.c/.h` | the sound board as a synthesizer: the tone generator from its counter (exact pitch); pops, springboard hit and miss approximated by ear |
| `shot.c/.h` | PNG writer for the headless shots |
| `platform\clowns_platform.h` | the platform contract |
| `platform\windows\plat_win.c` | the Windows backend: window, GDI blit, waveOut audio, mouse and keys, ini |
| `platform\headless\` | the quiet backend |
| `build_win.bat` | the window build |
| `build_all.bat`, `run_tests.bat` | headless program and lockstep; the 16 scenarios and the coverage report |
| `tests\lockstep.cpp` | the ROM on the 8080 core against the port (`--costs`, `--coverage`, `--free`, `--trace`) |
| `tests\i8080\`, `tests\deftypes.h` | AAE's `cpu_i8080` (Mike Chambers' 8080 core as converted for AAE) and the header it includes, copied unchanged; `sys_log.h` is a four-line shim |
| `tests\headless.c` | the headless runner |
| `tools\coverage.py` | which routines the scenarios executed |
| `shots\` | pictures from the headless runner: title, demo, GET READY, play, PLAYER JUMPS AGAIN, a splat, the switch test |

## Limits

- **Sound.** The tone generator's pitch is exact; the pops, the springboard hit and
  the miss sound are stand-ins tuned by ear, not models of the discrete circuits
  (MAME models them as an op-amp network and a sample).
- **The RAM test's picture.** A self-test pass is one C call, so the walking bit
  patterns the real screen shows during those 10.6 seconds are not displayed, and
  the coin switch that leaves for the switch test is only seen at the start of a
  pass (hold it at reset).
- **The coin counter** (`OUT_MISC` b0) goes nowhere.
- **No colour overlay**: the picture is the board's black and white.
