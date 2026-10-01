"""Generate clowns_program_rom.asm from the ROM image and the annotations.

Code is whatever trace.py reaches (reset, the two interrupt entries, and the
table-driven entries listed in notes.extra_entries); everything else is data and
must be described by notes.Layout.  Names, routine headers and comments come
from notes/*.txt.  The result is checked by verify.py, which shares nothing
with this file except the opcode table.
"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import i8080, notes, trace

OUT = os.path.join(HERE, "clowns_program_rom.asm")
REFS = os.path.join(HERE, "build", "program_refs.json")
RULE = ";" + "-" * 78
BANNER = ";" + "=" * 78
COMMENT_COL = 36

HEADER = """\
;Clowns (Midway, 1978) - annotated disassembly of the program ROM $0000-$17FF.
;MAME set 'clowns' (rev. 2): h2.cpu g2.cpu f2.cpu e2.cpu d2.cpu c2.cpu, 1K each.
;Intel 8080 on the Midway 8080 black & white board: 256 x 224 bitmap at $2400,
;MB14241 shifter on ports 1-3, tone generator and discrete sounds on ports 5-7.
;No source for this game is known; every name, routine header and comment was
;written for this disassembly from reading the code.  The hardware notes follow
;the MAME driver (mw8080bw.cpp).
;Every line below was re-encoded and byte-compared with the ROM (verify.py).
;Syntax: Intel 8080 mnemonics; directives as the Tempest / Space Duel listings
;(.org, .include, .alias, .byte, .word); $ is hex, < and > take the low and
;high byte, [ ] groups an expression.  Every code and data line starts with its
;address label Lxxxx; named labels sit on their own line above it.

.org $0000

.include "clowns_defines.asm"
"""

# LXI instructions whose 16-bit value is a ROM address (the rest are counts,
# coordinates and offsets, printed as hex unless notes/*.txt overrides them)
LXI_ROM = {
    0x00EF, 0x01B6, 0x01CE, 0x02A0, 0x033E, 0x0766, 0x07DC, 0x0A4B, 0x0A51,
    0x0B31, 0x0B5C, 0x0C43, 0x0D45, 0x0D6C, 0x0D72, 0x0DAC, 0x121F, 0x1225,
    0x132B, 0x1358, 0x136E, 0x13B3, 0x13C6, 0x13CC, 0x143C, 0x1442, 0x14DC,
    0x156C, 0x16CB, 0x16E7, 0x16F8, 0x1703, 0x17DD,
}

def hexv(v, width):
    return "$%0*X" % (width, v)

class Emitter:
    def __init__(self):
        self.mem = trace.load()
        self.notes = notes.load_notes()
        self.tr = trace.Trace(self.mem, notes.extra_entries(self.mem))
        if self.tr.bad:
            for a, why in self.tr.bad:
                print("!! trace: $%04X %s" % (a, why))
            raise SystemExit(1)
        self.refs = set()
        self.idents = set()

    def sym(self, a):
        """Label expression for a ROM address."""
        self.refs.add(a)
        return self.notes.labels.get(a, "L%04X" % a)

    def operand(self, a, d):
        mn, tmpl, val, size = d
        if val is None:
            return tmpl[1:] if tmpl.startswith("#") else tmpl
        ov = self.notes.operands.get(a)
        if ov is not None:
            text = ov
        elif mn in i8080.JUMPS or mn in i8080.CALLS:
            text = self.sym(val)
        elif mn in i8080.MEMREF:
            text = notes.ram_expr(val) or (self.sym(val) if val < notes.ROM_SIZE else hexv(val, 4))
        elif mn == "LXI":
            text = notes.ram_expr(val, exact=True) if not tmpl.startswith("SP") else None
            if text is None and a in LXI_ROM:
                text = self.sym(val)
            if text is None:
                text = hexv(val, 4)
        elif mn in ("IN", "OUT"):
            text = notes.port_name(mn, val) or hexv(val, 2)
        else:
            text = hexv(val, 2 if size == 2 else 4)
        return tmpl.replace("@16", text).replace("@8", text)

    def item(self, x, directive):
        if isinstance(x, int):
            return hexv(x, 2 if directive == ".byte" else 4)
        return x

    def build_lines(self, breaks):
        """[(addr, size, text, comment)] covering the whole ROM."""
        mem, tr = self.mem, self.tr
        lay = notes.Layout(mem, self.notes, self.sym, breaks)
        out, a = [], 0
        while a < len(mem):
            if a in tr.starts:
                d = tr.starts[a]
                out.append((a, d[3], "%-4s %s" % (d[0], self.operand(a, d)), self.notes.comments.get(a, "")))
                a += d[3]
                continue
            if a in tr.covered:
                raise SystemExit("!! $%04X is inside the instruction at $%04X" % (a, tr.covered[a]))
            ln = lay.lines.get(a)
            if ln is None:
                raise SystemExit("!! no data layout for $%04X (notes.Layout)" % a)
            directive, items, comment = ln
            size = len(items) * (2 if directive == ".word" else 1)
            for i in range(size):
                if (a + i) in tr.covered:
                    raise SystemExit("!! data line $%04X runs into code at $%04X" % (a, a + i))
                if i and (a + i) in lay.lines:
                    raise SystemExit("!! data line $%04X overlaps the one at $%04X" % (a, a + i))
            c = self.notes.comments.get(a)
            if c:
                comment = c if not comment else "%s  %s" % (comment, c)
            out.append((a, size, "%s %s" % (directive, ", ".join(self.item(x, directive) for x in items)), comment))
            a += size
        if a != len(mem):
            raise SystemExit("!! listing ends at $%04X" % a)
        stray = [x for x in lay.lines if x in tr.covered]
        if stray:
            raise SystemExit("!! data layout inside code at $%04X" % min(stray))
        return out

    def run(self):
        n = self.notes
        self.build_lines(set())                       # pass 1 collects referenced addresses
        lines = self.build_lines(set(self.refs))      # pass 2 starts a line at each of them
        starts = {a for a, _, _, _ in lines}
        problems = []
        for a in sorted(self.refs):
            if a not in starts:
                problems.append("referenced address $%04X is not the start of a line" % a)
        for kind, table in (("label", n.labels), ("header", n.headers), ("section", n.sections),
                            ("comment", n.comments), ("comment line", n.above), ("operand", n.operands)):
            for a in sorted(table):
                if a not in starts:
                    problems.append("%s at $%04X (%s) is not the start of a line" % (kind, a, n.where.get(a, "?")))
        for a in n.operands:
            if a not in self.tr.starts:
                problems.append("operand override at $%04X is not an instruction" % a)
        if problems:
            for p in problems:
                print("!! " + p)
            raise SystemExit(1)

        out = [HEADER]
        headers = 0
        for a, size, text, comment in lines:
            if a in n.sections:
                sec = n.sections[a]
                out += ["", BANNER, "; " + sec[0]] + [";   " + s for s in sec[1:]] + [BANNER]
            if a in n.headers:
                h = n.headers[a]
                out += ["", RULE, "; " + h[0]] + [";   " + s for s in h[1:]] + [RULE, n.labels[a] + ":"]
                headers += 1
            elif a in n.labels:
                out += ["", n.labels[a] + ":"]
            for s in n.above.get(a, []):
                out.append(";" + s)
            ln = "L%04X:  %s" % (a, text)
            if comment:
                ln = ln.ljust(COMMENT_COL - 1) + " ;" + comment
            out.append(ln.rstrip())
        with open(OUT, "w", newline="\n") as fp:
            fp.write("\n".join(out) + "\n")

        code = sum(s for a, s, _, _ in lines if a in self.tr.starts)
        os.makedirs(os.path.dirname(REFS), exist_ok=True)
        with open(REFS, "w") as fp:
            json.dump({"labels": {"%04X" % a: nm for a, nm in sorted(n.labels.items())},
                       "routines": ["%04X" % a for a in sorted(n.headers)]}, fp, indent=1)
        print("wrote %s" % os.path.basename(OUT))
        print("lines          : %d (%d instructions, %d data lines)" % (
            len(lines), len(self.tr.starts), len(lines) - len(self.tr.starts)))
        print("code bytes     : %d, data bytes %d" % (code, len(self.mem) - code))
        print("named labels   : %d, routine headers %d" % (len(n.labels), headers))
        print("commented lines: %d" % sum(1 for _, _, _, c in lines if c))

if __name__ == "__main__":
    Emitter().run()
