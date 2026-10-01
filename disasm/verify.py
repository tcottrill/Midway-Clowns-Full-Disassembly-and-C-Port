"""Read back clowns_program_rom.asm (+ clowns_defines.asm) and prove it reproduces
the ROM $0000-$17FF byte for byte.

Independent of emit.py: it only parses the two text files.  Every Lxxxx line is
re-encoded at the address its label states (operands and .byte/.word
expressions are evaluated from the .alias equates and the labels in the files)
and compared with the image; the Lxxxx lines must also cover the ROM exactly
once.  Comment-only lines, routine headers and blank lines are ignored.

Exit status 1 on any mismatch.
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import i8080

LISTING = os.path.join(HERE, "clowns_program_rom.asm")
DEFINES = os.path.join(HERE, "clowns_defines.asm")
IMAGE = os.path.join(HERE, "build", "clowns_cpu.bin")
LO, HI = 0x0000, 0x1800

LINE = re.compile(r"^L([0-9A-F]{4}):\s+(\S+)\s*(.*)$")
LABEL = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(;.*)?$")
ALIAS = re.compile(r"^\.alias\s+([A-Za-z_][A-Za-z0-9_]*)\s+([^;\s]+)\s*(;.*)?$")

class EvalError(Exception):
    pass

def strip_comment(s):
    return s.split(";", 1)[0].rstrip()

def tokenize(s):
    toks, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c.isspace():
            i += 1
        elif c == "$":
            j = i + 1
            while j < n and s[j] in "0123456789ABCDEFabcdef":
                j += 1
            if j == i + 1:
                raise EvalError("bad hex number in %r" % s)
            toks.append(("num", int(s[i + 1:j], 16)))
            i = j
        elif c.isdigit():
            j = i
            while j < n and s[j].isdigit():
                j += 1
            toks.append(("num", int(s[i:j])))
            i = j
        elif c.isalpha() or c == "_":
            j = i
            while j < n and (s[j].isalnum() or s[j] == "_"):
                j += 1
            toks.append(("id", s[i:j]))
            i = j
        elif c in "+-*<>[]":
            toks.append(("op", c))
            i += 1
        else:
            raise EvalError("bad character %r in %r" % (c, s))
    return toks

def evaluate(s, syms):
    """Expression value: unary - < >, then *, then + -.  [ ] groups."""
    toks = tokenize(s)
    pos = [0]

    def peek():
        return toks[pos[0]] if pos[0] < len(toks) else (None, None)

    def unary():
        t, v = peek()
        if t == "op" and v in "-<>":
            pos[0] += 1
            x = unary()
            return {"-": -x, "<": x & 0xFF, ">": (x >> 8) & 0xFF}[v]
        if t == "op" and v == "[":
            pos[0] += 1
            x = add()
            if peek() != ("op", "]"):
                raise EvalError("missing ] in %r" % s)
            pos[0] += 1
            return x
        if t == "num":
            pos[0] += 1
            return v
        if t == "id":
            pos[0] += 1
            if v not in syms:
                raise EvalError("undefined symbol %s" % v)
            return syms[v]
        raise EvalError("bad expression %r" % s)

    def mul():
        x = unary()
        while peek() == ("op", "*"):
            pos[0] += 1
            x *= unary()
        return x

    def add():
        x = mul()
        while True:
            t, v = peek()
            if t == "op" and v in "+-":
                pos[0] += 1
                y = mul()
                x = x + y if v == "+" else x - y
            else:
                return x

    x = add()
    if pos[0] != len(toks):
        raise EvalError("junk in %r" % s)
    return x

def encode_line(mn, oper, syms):
    """Bytes of one instruction line."""
    parts = [p.strip() for p in oper.split(",")] if oper.strip() else []
    if mn == "RST":
        if len(parts) != 1 or not parts[0].isdigit():
            raise EvalError("bad RST operand %r" % oper)
        out = i8080.encode(mn, "#" + parts[0])
    elif (mn, ",".join(parts)) in i8080.ENC and i8080.ENC[(mn, ",".join(parts))][1] is None:
        out = i8080.encode(mn, ",".join(parts))
    elif parts and (mn, ",".join(parts[:-1])) in i8080.ENC:
        out = i8080.encode(mn, ",".join(parts[:-1]), evaluate(parts[-1], syms))
    else:
        raise EvalError("unknown instruction %s %s" % (mn, oper))
    if out is None:
        raise EvalError("cannot encode %s %s" % (mn, oper))
    return out

def run(listing=LISTING, defines=DEFINES, rom_path=IMAGE, quiet=False):
    rom = open(rom_path, "rb").read()
    text = open(listing).read().splitlines()
    dtext = open(defines).read().splitlines() if os.path.exists(defines) else []
    syms, errors = {}, []

    def define(name, value, where):
        if name in syms and syms[name] != value:
            errors.append("%s redefined (%s)" % (name, where))
        syms[name] = value

    pending_alias = []
    for ln in dtext + text:
        m = ALIAS.match(ln.strip())
        if m:
            pending_alias.append((m.group(1), m.group(2)))
    pending = []
    for ln in text:
        m = LINE.match(ln)
        if m:
            a = int(m.group(1), 16)
            for nm in pending:
                define(nm, a, "label")
            pending = []
            define("L%04X" % a, a, "address label")
            continue
        m = LABEL.match(ln.strip())
        if m:
            pending.append(m.group(1))
    if pending:
        errors.append("labels at end of file: %s" % pending)
    left = pending_alias
    for _ in range(5):
        nxt = []
        for nm, ex in left:
            try:
                define(nm, evaluate(ex, syms), "alias")
            except EvalError:
                nxt.append((nm, ex))
        left = nxt
    for nm, ex in left:
        errors.append("cannot evaluate .alias %s %s" % (nm, ex))

    covered = {}
    total = bad = data = insn = 0
    for no, ln in enumerate(text, 1):
        m = LINE.match(ln)
        if not m:
            s = ln.strip()
            if s and not s.startswith(";") and not LABEL.match(s) and not ALIAS.match(s) \
                    and not s.startswith(".org") and not s.startswith(".include"):
                errors.append("line %d not understood: %s" % (no, s))
            continue
        a, mn, oper = int(m.group(1), 16), m.group(2), strip_comment(m.group(3))
        try:
            if mn in (".byte", ".word"):
                out = []
                for it in oper.split(","):
                    v = evaluate(it, syms)
                    if mn == ".byte":
                        if not 0 <= v <= 0xFF:
                            raise EvalError(".byte value out of range: %s" % it)
                        out.append(v)
                    else:
                        if not 0 <= v <= 0xFFFF:
                            raise EvalError(".word value out of range: %s" % it)
                        out += [v & 0xFF, v >> 8]
                data += len(out)
            else:
                out = encode_line(mn.upper(), oper, syms)
                insn += 1
        except EvalError as e:
            bad += 1
            errors.append("line %d $%04X: %s" % (no, a, e))
            continue
        for i, b in enumerate(out):
            ad = a + i
            if ad in covered:
                errors.append("$%04X emitted twice (lines %d and %d)" % (ad, covered[ad], no))
            covered[ad] = no
            total += 1
            if ad >= len(rom) or rom[ad] != b:
                bad += 1
                errors.append("line %d $%04X: %s %s -> $%02X, ROM has %s" % (
                    no, ad, mn, oper, b, "$%02X" % rom[ad] if ad < len(rom) else "nothing"))
    missing = [x for x in range(LO, HI) if x not in covered]
    outside = [x for x in covered if not LO <= x < HI]
    if missing:
        errors.append("%d ROM bytes not covered, first $%04X" % (len(missing), missing[0]))
    if outside:
        errors.append("%d bytes outside $0000-$17FF" % len(outside))
    nerr = bad + len(missing) + len(outside) + len([e for e in errors if "redefined" in e or "not understood" in e
                                                    or "cannot evaluate" in e or "twice" in e or "end of file" in e])
    if not quiet:
        print("verified bytes : %d of %d ($0000-$17FF)" % (total, HI - LO))
        print("instructions   : %d" % insn)
        print("data bytes     : %d" % data)
        print("symbols        : %d" % len(syms))
        print("MISMATCHES     : %d" % nerr)
        for e in errors[:20]:
            print("   " + e)
    return nerr

if __name__ == "__main__":
    sys.exit(1 if run() else 0)
