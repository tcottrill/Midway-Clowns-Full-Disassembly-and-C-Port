"""Hand-written knowledge about the Clowns ROM that the listing generators merge
with the bytes: where the data is and how it is laid out, the extra code
entries the tracer cannot find, the RAM / port / constant names, and the text
annotations in notes/*.txt (labels, routine headers, inline comments).

Nothing here is trusted by verify.py: every line emit.py prints from these
tables is re-encoded and compared with the ROM.
"""
import glob, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROM_SIZE = 0x1800

# ----------------------------------------------------------------------------
# Code the tracer cannot reach by following jumps and calls.
# ----------------------------------------------------------------------------
SCRIPT_OPS_AT = 0x1413          # word table, opcode 2..$20 -> handler
FRAME_TASKS_AT = 0x0ABF         # 6 x (routine, HL argument)

def extra_entries(mem):
    out = [(0x01DE, "return address pushed at $01B6")]
    for i in range(16):
        a = SCRIPT_OPS_AT + 2 * i
        out.append((mem[a] | (mem[a + 1] << 8), "script opcode $%02X" % (2 * i + 2)))
    for i in range(6):
        a = FRAME_TASKS_AT + 4 * i + 2
        out.append((mem[a] | (mem[a + 1] << 8), "balloon task %d" % i))
    return out

# ----------------------------------------------------------------------------
# Memory map, ports, RAM variables, constants (clowns_defines.asm).
# (name, value, comment)
# ----------------------------------------------------------------------------
MEMORY_MAP = [
    ("ProgramRom", 0x0000, "Through $17FF. Six 1K ROMs H G F E D C (clowns_program_rom.asm)."),
    ("WorkRam", 0x2000, "Through $23FF. Variables; the 8080 stack grows down from $2400."),
    ("VideoRam", 0x2400, "Through $3FFF. 256 x 224 bitmap, 32 bytes per line, bit 0 = leftmost pixel. Address = $2400 + 32*Y + X/8."),
    ("EmptyRomSpace", 0x4000, "Through $5FFF. The board's second ROM area, not fitted on Clowns: writes are ignored. A splatted clown sinking below line 223 is drawn into it."),
    ("RamMirror", 0x6000, "Through $7FFF. $2000-$3FFF again (only 15 address bits are decoded). Not used."),
]

# I/O ports.  The 8080 has a separate 8-bit port space; IN and OUT with the
# same number are different devices.
PORTS_IN = [
    ("INP_PADDLE", 0x00, "IN0. Paddle position 0-255 of the player selected by OUT_MISC bit 1."),
    ("INP_SWITCH", 0x01, "IN1, active low. b4 2-player start, b5 1-player start, b6 coin."),
    ("INP_DIP", 0x02, "IN2. b0-b1 coinage (0 1C/1P, 1 1C/2P, 2 2C/2P, 3 2C/1P), b2-b3 bonus game (0 none, 9000, 11000, 13000), b4 balloon resets (0 each row, 1 all rows), b5 extra jump at 3000/4000, b6 jumps 3/4, b7 self test."),
    ("INP_SHIFT", 0x03, "MB14241 shifter result: the last two bytes written, shifted by the count."),
]
PORTS_OUT = [
    ("OUT_SHIFT_AMT", 0x01, "MB14241 shift count (low 3 bits = X position within the byte)."),
    ("OUT_SHIFT_DATA", 0x02, "MB14241 shift data."),
    ("OUT_MISC", 0x03, "b0 coin counter, b1 paddle select (1 = player 2). Shadow in OUT3_SHADOW."),
    ("OUT_WATCHDOG", 0x04, "Any write clears the watchdog."),
    ("OUT_TONE_LO", 0x05, "Tone generator: b0 tone enable, b1-b5 low five bits of the period."),
    ("OUT_TONE_HI", 0x06, "Tone generator: b0-b5 high six bits of the period."),
    ("OUT_SOUND", 0x07, "b0 pop (bottom row), b1 pop (middle row), b2 pop (top row), b3 sound enable, b4 springboard hit, b5 miss (rising edge)."),
]

# RAM.  (address, name, size, comment); size > 1 lets NAME+n resolve.
RAM = [
    (0x2000, "SCRIPT_PTR", 2, "Game script program counter (the interpreter is MainLoop)."),
    (0x2002, "SECOND_PRESCALE", 1, "Counts 30 odd frames down to one TMR_TIMEOUT tick (about a second)."),
    (0x2003, "TIMEOUT_PTR", 2, "Script address taken when TMR_TIMEOUT runs out (script TIMEOUT command)."),
    (0x2005, "GAME_ACTIVE", 1, "0 = attract mode, 1 = a game is being played."),
    (0x2006, "COIN_SW_PREV", 1, "Last coin switch state ($40 = down) for edge detection."),
    (0x2007, "RNG_SEED", 1, "8-bit shift-register random number."),
    (0x2009, "COINS", 1, "Coins inserted and not yet spent."),
    (0x200A, "COINS_PER_GAME", 1, "Coins the current game cost; a bonus game adds this many back to COINS."),
    (0x200B, "SCRIPT_HOLD", 1, "Non-zero: an expired TMR_SCRIPT does not step the script past its WAIT."),
    (0x200C, "TIMEOUT_HOLD", 1, "Non-zero: an expired TMR_TIMEOUT does not jump to TIMEOUT_PTR."),
    (0x200D, "FRAME_CTR", 1, "Incremented each frame; bit 0 picks seesaw frame (even) or balloon frame (odd)."),
    (0x200E, "P1_SCORE", 2, "Player 1 score, BCD, high byte first. Shown with a fixed 0 appended (tens of points)."),
    (0x2010, "JUMPS_LEFT", 1, "Jumps (lives) left, shown after JUMPS."),
    (0x2011, "P2_SCORE", 2, "Player 2 score, same format as P1_SCORE."),
    (0x2013, "PADDLE_POS", 1, "Wanted seesaw X: the paddle (read at vblank when PADDLE_ENABLE) or the attract autopilot."),
    (0x2014, "OUT3_SHADOW", 1, "Copy of OUT_MISC: b0 coin counter, b1 paddle select."),
    (0x2015, "HI_SCORE", 2, "High score, BCD, high byte first. Below $2040, so it survives the script CLEAR."),
    (0x2017, "REFILL_PENDING", 1, "Non-zero while a cleared row waits to be refilled: the row's Y (each-row mode) or 1 (all rows)."),
    (0x2018, "REFILL_ROW_PTR", 2, "Balloon row (or first row) that TMR_REFILL will refill."),
    (0x201A, "NEXT_PLAYER", 1, "Player for the next turn; ClearRamTop copies it to PLAYER."),
    (0x201B, "NEXT_JUMPS_LEFT", 1, "Jumps left for the next turn; ClearRamTop copies it to JUMPS_LEFT."),
    (0x201C, "SPEED_LEVEL", 1, "0-4. Launch speed is SPEED_LEVEL+5; goes up every third launch."),
    (0x201D, "TUNE_TEMPO", 1, "Frames per beat of the tune being played."),
    (0x201E, "TUNE_TICKS", 1, "Frames left in the current beat."),
    (0x201F, "TUNE_BEATS", 1, "Beats left in the current note."),
    (0x2020, "TUNE_GAP", 1, "Frames of silence owed before the next note."),
    (0x2021, "TUNE_ON", 1, "Non-zero: PlayTune runs."),
    (0x2022, "TUNE_PTR", 2, "Next byte of the tune."),
    (0x2024, "JUMPS_AGAIN", 1, "Non-zero: the player earned an extra jump; the turn does not pass and no jump is used."),
    (0x2025, "PREV_BONUS_GAME", 1, "BONUS_GAME of the game that just ended; a game played on a bonus cannot win another."),
    (0x2028, "TMR_TIMEOUT", 1, "Slow timer (seconds). Expiry -> EVT_TIMEOUT b0 -> script jumps to TIMEOUT_PTR."),
    (0x2029, "TMR_SCRIPT", 1, "30 Hz timers $2029-$2030 (TickTimers). This one: script DELAY; expiry steps past the WAIT."),
    (0x202A, "TMR_SOUND_OFF", 1, "Expiry ends the pop / hit / miss sound (OUT_SOUND = $08)."),
    (0x202B, "TMR_WALK", 1, "Expiry advances the walk animation of the clown being served."),
    (0x202C, "TMR_SERVE_JUMP", 1, "Expiry makes the served clown jump off its ledge."),
    (0x202D, "TMR_GRAVITY", 1, "Expiry adds 1 to the flyer's Y velocity; reloaded from GRAVITY_PERIOD."),
    (0x202E, "TMR_SPLAT", 1, "Expiry steps the splat animation."),
    (0x202F, "TMR_HIT_LOCKOUT", 1, "While running, sprite contact is ignored (after a launch or a pop). No expiry action."),
    (0x2030, "TMR_REFILL", 1, "Expiry refills the cleared balloon row(s)."),
    (0x2031, "TMR_COIN_CTR", 1, "30 Hz timers $2031-$2033. This one: expiry ends the coin counter pulse."),
    (0x2032, "TMR_TUMBLE", 1, "Paces the flyer's tumble frames. No expiry action; polled by AnimateFlyer."),
    (0x2033, "TMR_FREEZE", 1, "Expiry ends the bonus freeze and erases the BONUS message."),
    (0x2040, "P1_ROW_TOP", 36, "Balloon rows: 12 balloons x (state b7 = present, X, Y). Player 1 top row (Y $24, 100 points)."),
    (0x2064, "P2_ROW_TOP", 36, "Player 2 top row. Every player 2 row is P2_OFFSET above player 1's."),
    (0x2088, "P1_ROW_MID", 36, "Player 1 middle row (Y $38, 50 points)."),
    (0x20AC, "P2_ROW_MID", 36, "Player 2 middle row."),
    (0x20D0, "P1_ROW_BOT", 36, "Player 1 bottom row (Y $4E, 20 points)."),
    (0x20F4, "P2_ROW_BOT", 36, "Player 2 bottom row."),
    (0x2118, "SEESAW_STATE", 1, "b7 on screen, b6 tipping, b5 right end down (clown waits on the right), b0-b3 picture 0-4."),
    (0x2119, "SEESAW_DRAWN_X", 1, "X the seesaw was last drawn at (erased from here next time)."),
    (0x211B, "P1_EXTRA_JUMP", 1, "Non-zero once player 1 has been given the extra jump."),
    (0x211C, "P2_EXTRA_JUMP", 1, "Same for player 2."),
    (0x211D, "PLAYER", 1, "$00 = player 1, $FF = player 2."),
    (0x211E, "TWO_PLAYERS", 1, "Non-zero in a two-player game."),
    (0x211F, "BONUS_GAME", 1, "Non-zero once the bonus game has been awarded in this game."),
    (0x2180, "CLOWN_A", 64, "Clown object (see the CL_ offsets)."),
    (0x21C0, "CLOWN_B", 64, "Second clown object."),
    (0x2200, "TEXT_BUF", 15, "Characters of the score line: player 1 score (5), jumps left (1), player 2 score (5)."),
    (0x220F, "BONUS_BUF", 5, "Characters of the row bonus value."),
    (0x2219, "EVT_TIMEOUT", 1, "b0 set by the interrupt when TMR_TIMEOUT ran out; taken by CheckTimeout."),
    (0x221A, "EVT_TIMERS", 1, "Expiry bits for $2029-$2030 (b7 = $2029 ... b0 = $2030); taken by RunTimerEvents."),
    (0x221B, "EVT_TIMERS2", 1, "Expiry bits for $2031-$2033 (b2 = $2031 ... b0 = $2033); taken by RunTimerEvents2."),
    (0x221D, "SEESAW_X", 1, "Seesaw X: PADDLE_POS limited to $D7."),
    (0x221E, "SERVE_REQUEST", 1, "Non-zero: ServeClown sets up both clowns for a new jump."),
    (0x221F, "SERVING", 1, "Non-zero while the served clown walks on its ledge (no gravity, no tumbling)."),
    (0x2220, "WALK_PHASE", 1, "0-3, steps the walk picture +1 +1 -1 -1."),
    (0x2221, "GRAVITY_PERIOD", 1, "TMR_GRAVITY reload: 5 in attract, 4 at the start of a jump, up to 8."),
    (0x2222, "GRAVITY_STEP_CTR", 1, "Every 2nd launch raises GRAVITY_PERIOD."),
    (0x2223, "SPLAT_CTR", 1, "Splat pictures left."),
    (0x2224, "FLYER_PTR", 2, "Clown object in the air (or being served)."),
    (0x2226, "RIDER_PTR", 2, "Clown object standing on the seesaw."),
    (0x2228, "ERASE_MODE", 1, "OR-ed into the flyer's state when it is drawn: $40 put the saved background back, $20 blank the box."),
    (0x2229, "HIT_ROW", 1, "Row of the balloon just popped: 0 bottom, 1 middle, 2 top."),
    (0x222A, "START1_DOWN", 1, "$20 while the 1-player start button is down."),
    (0x222B, "START2_DOWN", 1, "$10 while the 2-player start button is down."),
    (0x222C, "PLAYFIELD_ON", 1, "Non-zero: the floor and the four ledges are redrawn every main loop pass."),
    (0x222D, "PADDLE_ENABLE", 1, "Non-zero: the vblank interrupt copies the paddle to PADDLE_POS."),
    (0x222E, "AUTOPILOT", 1, "Non-zero: attract mode steers the seesaw under the flyer."),
    (0x2230, "DIGIT_INDEX", 1, "Which character of TEXT_BUF DrawNextDigit shows next."),
    (0x2231, "FLYER_HIGH", 1, "Non-zero when the flyer is above Y $50: it is then updated at mid-screen, else at vblank."),
    (0x2232, "FREEZE", 1, "Non-zero: flyer and balloons stand still (bonus message)."),
    (0x2233, "FREEZE_REQ", 1, "Copied to FREEZE after the flyer's next update."),
    (0x2234, "CONTACT_ROW", 1, "Set by the interrupt: 1 + sprite row where the flyer first touched something; cleared by HandleContact."),
    (0x2235, "BALLOON_PHASE", 1, "0-5, which entry of BalloonTasks runs this odd frame."),
    (0x2236, "SPEED_STEP_CTR", 1, "Every 3rd launch raises SPEED_LEVEL."),
    (0x2237, "REBOUND_STEP_CTR", 1, "Every 4th launch raises REBOUND_SPEED."),
    (0x2238, "REBOUND_SPEED", 1, "0-4. Downward speed given to a flyer that pops a balloon on the way up."),
]

CONSTANTS = [
    ("Clown object", [
        ("CL_STATE", 0x00, "b7 in use, b6 put back the saved background before the next draw, b5 blank the old box, b4 slow (moves every 4th update), b3 splatted, b0-b2 slow tick."),
        ("CL_FRAME", 0x01, "Picture number, index into ClownPictures."),
        ("CL_XVEL", 0x02, "Added to X at every update."),
        ("CL_X", 0x03, "X, 0-$F1."),
        ("CL_YVEL", 0x04, "Added to Y at every update."),
        ("CL_Y", 0x05, "Y of the top of the picture."),
        ("CL_SCREEN", 0x06, "Video RAM address the picture was drawn at (2 bytes)."),
        ("CL_ROWS", 0x08, "Rows drawn."),
        ("CL_WIDTH", 0x09, "Screen bytes per row: picture bytes + 1 for the shift (3 for the flyer, 2 for the rider)."),
        ("CL_SAVED", 0x0A, "Background bytes saved while drawing, CL_WIDTH per row."),
    ]),
    ("Balloons", [
        ("P2_OFFSET", 0x24, "Player 2's balloon row = player 1's + $24 (12 balloons x 3 bytes)."),
    ]),
]

RAM_BY_ADDR = {}
for _a, _n, _sz, _c in RAM:
    for _i in range(_sz):
        RAM_BY_ADDR.setdefault(_a + _i, (_n, _i))

def ram_expr(addr, exact=False):
    """Symbolic expression for a RAM address, or None."""
    e = RAM_BY_ADDR.get(addr)
    if e is None:
        return None
    name, off = e
    if off == 0:
        return name
    return None if exact else "%s+%d" % (name, off)

def port_name(mn, num):
    for name, v, _ in (PORTS_IN if mn == "IN" else PORTS_OUT):
        if v == num:
            return name
    return None

# ----------------------------------------------------------------------------
# Text annotations: notes/*.txt
#   ## AAAA Title            section banner (+ indented continuation lines)
#   == AAAA Name - text      routine header and label (+ indented continuation lines)
#   @  AAAA Name             label only
#   ^AAAA text               comment-only line above the statement at AAAA
#   op AAAA expression       operand override for the value of the instruction at AAAA
#   AAAA text                inline comment
#   ; ...                    remark in the notes file itself
# ----------------------------------------------------------------------------
class Notes:
    def __init__(self):
        self.labels = {}        # addr -> name
        self.headers = {}       # addr -> [lines]
        self.sections = {}      # addr -> [lines]
        self.comments = {}      # addr -> text
        self.above = {}         # addr -> [lines]
        self.operands = {}      # addr -> expression
        self.where = {}         # addr -> file:line of the first annotation (diagnostics)

def load_notes():
    n = Notes()
    cont = None
    for path in sorted(glob.glob(os.path.join(HERE, "notes", "*.txt"))):
        for no, raw in enumerate(open(path, encoding="utf-8").read().splitlines(), 1):
            where = "%s:%d" % (os.path.basename(path), no)
            if not raw.strip() or raw.startswith(";"):
                continue
            if raw[0] in " \t":
                if cont is None:
                    raise SystemExit("%s: continuation line without a header" % where)
                cont.append(raw.strip())
                continue
            cont = None
            m = re.match(r"^(##|==|@|op)\s+([0-9A-Fa-f]{4})\s+(.*)$", raw)
            if m:
                kind, a, rest = m.group(1), int(m.group(2), 16), m.group(3).strip()
                n.where.setdefault(a, where)
                if kind == "##":
                    cont = n.sections.setdefault(a, [])
                    cont.append(rest)
                elif kind == "==":
                    name = rest.split()[0]
                    if a in n.labels and n.labels[a] != name:
                        raise SystemExit("%s: $%04X already labelled %s" % (where, a, n.labels[a]))
                    n.labels[a] = name
                    cont = n.headers.setdefault(a, [])
                    cont.append(rest)
                elif kind == "@":
                    if a in n.labels:
                        raise SystemExit("%s: $%04X already labelled %s" % (where, a, n.labels[a]))
                    n.labels[a] = rest
                else:
                    n.operands[a] = rest
                continue
            m = re.match(r"^\^([0-9A-Fa-f]{4})\s+(.*)$", raw)
            if m:
                a = int(m.group(1), 16)
                n.where.setdefault(a, where)
                n.above.setdefault(a, []).append(m.group(2).strip())
                continue
            m = re.match(r"^([0-9A-Fa-f]{4})\s+(.*)$", raw)
            if m:
                a = int(m.group(1), 16)
                n.where.setdefault(a, where)
                if a in n.comments:
                    raise SystemExit("%s: $%04X already has a comment" % (where, a))
                n.comments[a] = m.group(2).strip()
                continue
            raise SystemExit("%s: line not understood: %s" % (where, raw))
    names = {}
    for a, nm in n.labels.items():
        if nm in names:
            raise SystemExit("label %s used for $%04X and $%04X" % (nm, names[nm], a))
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", nm):
            raise SystemExit("bad label %r at $%04X" % (nm, a))
        names[nm] = a
    return n

# ----------------------------------------------------------------------------
# Data layout.  layout(mem, notes) returns {addr: (directive, [items], comment)}
# for every data line; an item is an int (printed as hex) or an expression.
# ----------------------------------------------------------------------------
def bits(b):
    return "".join("#" if b & (1 << i) else "." for i in range(8))

def word(mem, a):
    return mem[a] | (mem[a + 1] << 8)

SCRIPT_OPS = {
    0x00: ("WAIT", ""), 0x02: ("TEXT", "bpw"), 0x04: ("DELAY", "b"), 0x06: ("TIMEOUT", "bp"),
    0x08: ("GOTO", "p"), 0x0A: ("SET", "bp"), 0x0C: ("CLEAR", "b"), 0x0E: ("SCORE", "pw"),
    0x10: ("BIGTEXT", "bpw"), 0x12: ("IFZ", "pp"), 0x14: ("IFNZ", "pp"), 0x16: ("COINSTART", ""),
    0x18: ("ROW", "bp"), 0x1A: ("DECCOIN", ""), 0x1C: ("INCCOIN", ""), 0x1E: ("TONE", ""),
    0x20: ("QUIET", ""),
}
SCRIPT_RANGE = (0x0DF4, 0x10AB)
TEXT_RANGES = [(0x10B3, 0x117A), (0x13D4, 0x13E6), (0x15A0, 0x15AC)]
FONT_AT, FONT_CHARS = 0x055E, "0123456789@ABCDEFGHIJKLMNOPQRSTUVW"
CLOWN_PTRS, CLOWN_COUNT = 0x0812, 18
SEESAW_PTRS, SEESAW_COUNT = 0x0374, 5
NOTE_TABLE, NOTE_COUNT = 0x02AE, 38
TUNES = [(0x0DBF, 0x0DD9), (0x0DD9, 0x0DF3)]

def screen_pos(a):
    """'col,line' text for a video RAM address."""
    o = a - 0x2400
    return "col %d, line %d" % (o % 32, o // 32)

def glyph_text(mem, a, n):
    """Text as the game shows it: @ is the blank, Q is drawn as Y, K as a down arrow."""
    out = ""
    for i in range(n):
        c = chr(mem[a + i])
        out += {"@": " ", "Q": "Y", "K": "v"}.get(c, c)
    return out

class Layout:
    def __init__(self, mem, notes, sym, breaks=()):
        """sym(addr) -> label expression for a ROM address (named label or Lxxxx).
        breaks: addresses a data line has to start at (labels and referenced addresses)."""
        self.mem, self.notes, self.sym = mem, notes, sym
        self.breaks = set(breaks) | set(notes.labels)
        self.lines = {}
        self.build()

    def put(self, a, directive, items, comment=""):
        if a in self.lines:
            raise SystemExit("data line $%04X defined twice" % a)
        self.lines[a] = (directive, items, comment)

    def raw(self, a, b, per=8, comment="", first_only=True):
        """Plain .byte rows for [a, b], broken at labels."""
        mem, x, first = self.mem, a, True
        while x <= b:
            y = x + 1
            while y <= b and y - x < per and y not in self.breaks:
                y += 1
            self.put(x, ".byte", list(mem[x:y]), comment if (first or not first_only) else "")
            first = False
            x = y

    def ptr(self, v):
        """Expression for a pointer value: RAM symbol, ROM label, or hex."""
        e = ram_expr(v)
        if e:
            return e
        if v < ROM_SIZE:
            return self.sym(v)
        return v

    def lohi(self, v):
        e = self.ptr(v)
        if isinstance(e, int):
            return [v & 0xFF, v >> 8]
        if "+" in e:
            e = "[" + e + "]"
        return ["<" + e, ">" + e]

    def script(self):
        mem = self.mem
        a, end = SCRIPT_RANGE
        while a < end:
            op = mem[a]
            name, fmt = SCRIPT_OPS[op]
            items, p, args = [op], a + 1, []
            for f in fmt:
                if f == "b":
                    items.append(mem[p])
                    args.append(mem[p])
                    p += 1
                else:
                    v = word(mem, p)
                    items += self.lohi(v) if f == "p" else [v & 0xFF, v >> 8]
                    args.append(v)
                    p += 2
            def nm(v):
                e = self.ptr(v)
                return "$%04X" % v if isinstance(e, int) else e
            if name in ("TEXT", "BIGTEXT"):
                c = '%s "%s" at %s' % (name, glyph_text(mem, args[1], args[0]), screen_pos(args[2]))
            elif name == "DELAY":
                c = "DELAY %d ticks" % args[0]
            elif name == "TIMEOUT":
                c = "TIMEOUT %d s -> %s" % (args[0], nm(args[1]))
            elif name == "GOTO":
                c = "GOTO %s" % nm(args[0])
            elif name == "SET":
                c = "SET %s = $%02X" % (nm(args[1]), args[0])
            elif name == "CLEAR":
                c = "CLEAR $%04X-$3FFF" % (0x4000 - 32 * args[0])
            elif name == "SCORE":
                c = "SCORE %s at %s" % (nm(args[0]), screen_pos(args[1]))
            elif name in ("IFZ", "IFNZ"):
                c = "%s %s GOTO %s" % (name, nm(args[0]), nm(args[1]))
            elif name == "ROW":
                c = "ROW %s Y=$%02X" % (nm(args[1]), args[0])
            else:
                c = name
            self.put(a, ".byte", items, c)
            a = p

    def text(self, a, b, per=8):
        mem, x = self.mem, a
        while x <= b:
            if mem[x] == 0:
                self.put(x, ".byte", [0], "unused")
                x += 1
                continue
            y = x + 1
            while y <= b and y - x < per and y not in self.breaks and mem[y] != 0:
                y += 1
            self.put(x, ".byte", list(mem[x:y]), '"%s"' % glyph_text(mem, x, y - x))
            x = y

    def build(self):
        mem = self.mem
        # ROM test table: (checksum complement, ROM letter) x 6, then the balance byte
        for i, sock in enumerate("HGFEDC"):
            a = 0x012B + 2 * i
            self.put(a, ".byte", [mem[a], mem[a + 1]],
                     "ROM %s $%04X-$%04X: check byte, letter shown if the sum is wrong" % (sock, 0x400 * i, 0x400 * i + 0x3FF))
        self.put(0x0137, ".byte", [mem[0x0137]], "not read by the test; presumably the byte adjusted to make ROM H add up")
        # note periods
        for i in range(NOTE_COUNT):
            a = NOTE_TABLE + 2 * i
            lo, hi = mem[a], mem[a + 1]
            preset = ((hi & 0x3F) << 6) | (((lo >> 1) & 0x1F) << 1)
            self.put(a, ".byte", [lo, hi],
                     "note $%02X: %s" % (i, "rest (tone off)" if not lo & 1 else
                                         "preset %d, %.0f Hz" % (preset, 998400.0 / (4096 - preset) / 2)))
        self.put(0x02FA, ".byte", [mem[0x02FA]], "unused")
        # seesaw pictures
        for i in range(SEESAW_COUNT):
            a = SEESAW_PTRS + 2 * i
            self.put(a, ".word", [self.sym(word(mem, a))], "picture %d" % i)
        for i in range(SEESAW_COUNT):
            a = word(mem, SEESAW_PTRS + 2 * i)
            rows = mem[a]
            self.put(a, ".byte", [rows], "%d rows of 5 bytes, bottom row first" % rows)
            for r in range(rows):
                x = a + 1 + 5 * r
                self.put(x, ".byte", list(mem[x:x + 5]), "".join(bits(v) for v in mem[x:x + 5]))
        self.put(0x041E, ".byte", [mem[0x041E]], "unused")
        # font
        for i, ch in enumerate(FONT_CHARS):
            shown = {"@": "blank", "Q": "Q, drawn as Y", "K": "K, drawn as a down arrow"}.get(ch, ch)
            for r in range(10):
                a = FONT_AT + 10 * i + r
                self.put(a, ".byte", [mem[a]], bits(mem[a]) + ("  '%s' (%s)" % (ch, shown) if r == 0 else ""))
        # rider picture, clown pictures
        for r in range(16):
            a = 0x0802 + r
            self.put(a, ".byte", [mem[a]], bits(mem[a]) + ("  (not drawn)" if r == 15 else ""))
        for i in range(CLOWN_COUNT):
            a = CLOWN_PTRS + 2 * i
            self.put(a, ".word", [self.sym(word(mem, a))], "picture $%02X" % i)
        for i in range(CLOWN_COUNT):
            a = word(mem, CLOWN_PTRS + 2 * i)
            rows, wd = mem[a], mem[a + 1]
            self.put(a, ".byte", [rows, wd], "%d rows, %d bytes wide" % (rows, wd))
            for r in range(rows):
                x = a + 2 + wd * r
                self.put(x, ".byte", list(mem[x:x + wd]), "".join(bits(v) for v in mem[x:x + wd]))
        self.put(0x0A40, ".byte", [mem[0x0A40]], "unused")
        # balloon tasks: first balloon of the pass, routine
        for i in range(6):
            a = FRAME_TASKS_AT + 4 * i
            arg = word(mem, a)
            e = ram_expr(arg)
            self.put(a, ".word", [e if e else arg, self.sym(word(mem, a + 2))],
                     "phase %d: %s balloons of the %s row move %s" % (
                         i, "even" if i < 3 else "odd", ("top", "middle", "bottom")[i % 3],
                         "left" if i % 3 == 1 else "right"))
        # balloon pictures
        for a in range(0x0B93, 0x0BA3):
            self.put(a, ".byte", [mem[a]], bits(mem[a]))
        self.put(0x0BA3, ".byte", [mem[0x0BA3]], "unused")
        # serve table
        side = {0x00: "left", 0xF0: "right"}
        for i in range(4):
            a = 0x0BF4 + 6 * i
            r = mem[a:a + 6]
            self.put(a, ".byte", list(r), "Y=$%02X YVEL=%d X=$%02X XVEL=%d FRAME=$%02X STATE=$%02X: %s %s ledge" % (
                r[0], r[1], r[2], r[3] - 256 * (r[3] > 127), r[4], r[5], "upper" if r[0] == 0x68 else "lower", side[r[2]]))
        self.put(0x0C0C, ".byte", [mem[0x0C0C]], "unused")
        # score line screen positions
        what = ["player 1 score"] * 5 + ["jumps left"] + ["player 2 score"] * 5
        for i in range(11):
            a = 0x0C8A + 2 * i
            self.put(a, ".word", [word(mem, a)], "%s (%s)" % (what[i], screen_pos(word(mem, a))))
        # bonus tables, tunes
        self.put(0x0DB3, ".byte", [mem[0x0DB3], mem[0x0DB4]], "all rows cleared: 2000 points")
        for i, rowname in enumerate(("bottom", "middle", "top")):
            a = 0x0DB5 + 3 * i
            self.put(a, ".byte", list(mem[a:a + 3]),
                     "%s row (Y $%02X) cleared: %d points" % (
                         rowname, mem[a], 10 * int("%x%02x" % (mem[a + 1], mem[a + 2]))))
        self.put(0x0DBE, ".byte", [mem[0x0DBE]], "unused")
        for a, b in TUNES:
            self.put(a, ".byte", [mem[a]], "tempo: %d frames per beat" % (mem[a] & 0x7F))
            x = a + 1
            while mem[x]:
                beats, note = mem[x], mem[x + 1]
                self.put(x, ".byte", [beats, note], "%d beat%s of note $%02X%s" % (
                    beats, "" if beats == 1 else "s", note & 0x7F,
                    " (rest)" if note & 0x7F == 0 else (", no gap after it" if note & 0x80 else "")))
                x += 2
            self.put(x, ".byte", [0], "end of tune")
            if x + 1 < b:
                self.put(x + 1, ".byte", list(mem[x + 1:b]), "unused")
        self.put(0x0DF3, ".byte", [mem[0x0DF3]], "unused")
        self.script()
        # coinage dispatch
        coinage = ["1 coin 1 player", "1 coin 2 players", "2 coins 2 players", "2 coins 1 player"]
        for i in range(4):
            a = 0x10AB + 2 * i
            self.put(a, ".word", [self.sym(word(mem, a))], "coinage %d: %s" % (i, coinage[i]))
        for a, b in TEXT_RANGES:
            if b == 0x15AC:
                self.text(a, b - 1, per=3)      # four 3-letter splat words
            else:
                self.text(a, b)
        # script opcode handlers
        for i in range(16):
            a = SCRIPT_OPS_AT + 2 * i
            self.put(a, ".word", [self.sym(word(mem, a))], "$%02X %s" % (2 * i + 2, SCRIPT_OPS[2 * i + 2][0]))
        # pop table
        for i, rowname in enumerate(("bottom", "middle", "top")):
            a = 0x17F9 + 2 * i
            self.put(a, ".byte", [mem[a], mem[a + 1]],
                     "%s row: %x0 points, OUT_SOUND value" % (rowname, mem[a]))
        self.put(0x17FF, ".byte", [mem[0x17FF]], "unused")
        # one-byte gaps between routines
        for a in (0x000F, 0x0017, 0x0236, 0x02AD, 0x0475, 0x04BA, 0x0B16, 0x1348, 0x1525):
            self.put(a, ".byte", [mem[a]], "unused")
