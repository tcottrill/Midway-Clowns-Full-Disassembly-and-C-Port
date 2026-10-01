"""Recursive-descent code tracer for the Clowns image.

Follows control flow from the entry points (reset, the two RST interrupt
entries, plus the extra entries a caller passes in: jump-table targets that are
only reached through PCHL) and records

    starts   {addr: (mnemonic, template, value, size)}  every instruction start
    covered  {addr: start}                              every byte of an instruction
    xrefs    {target: [(from, kind)]}                   kind: jump / call / entry
    drefs    {addr: [(from, kind)]}                     kind: r / w (LDA STA LHLD SHLD) or i (LXI)
    bad      [(addr, reason)]                           undocumented opcode or overlap reached

Tracing stops at JMP / RET / PCHL / HLT.  `stops` lists addresses the tracer
must not run into (data that follows a call which never returns).
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import i8080

IMAGE = os.path.join(HERE, "build", "clowns_cpu.bin")
ENTRIES = [(0x0000, "reset"), (0x0008, "RST 1"), (0x0010, "RST 2")]

def load():
    return open(IMAGE, "rb").read()

class Trace:
    def __init__(self, mem, entries=(), stops=()):
        self.mem = mem
        self.starts, self.covered = {}, {}
        self.xrefs, self.drefs, self.bad = {}, {}, []
        self.stops = set(stops)
        work = []
        for a, why in list(ENTRIES) + list(entries):
            self.xrefs.setdefault(a, []).append((None, "entry: " + why))
            work.append(a)
        while work:
            self._run(work.pop(), work)

    def _run(self, a, work):
        mem = self.mem
        while 0 <= a < len(mem):
            if a in self.starts or a in self.stops:
                return
            if a in self.covered:
                self.bad.append((a, "inside the instruction at $%04X" % self.covered[a]))
                return
            d = i8080.decode(mem, a)
            if d is None:
                self.bad.append((a, "undocumented opcode $%02X" % mem[a]))
                return
            mn, tmpl, val, size = d
            if any((a + i) in self.covered for i in range(size)):
                self.bad.append((a, "runs into another instruction"))
                return
            self.starts[a] = d
            for i in range(size):
                self.covered[a + i] = a
            if mn in i8080.JUMPS or mn in i8080.CALLS:
                self.xrefs.setdefault(val, []).append((a, "call" if mn in i8080.CALLS else "jump"))
                if val < len(mem):
                    work.append(val)
            elif mn == "RST":
                t = 8 * int(tmpl[1:])
                self.xrefs.setdefault(t, []).append((a, "call"))
                work.append(t)
            elif mn in i8080.MEMREF:
                self.drefs.setdefault(val, []).append((a, i8080.MEMREF[mn]))
            elif mn == "LXI":
                self.drefs.setdefault(val, []).append((a, "i"))
            if mn in i8080.STOPS:
                return
            a += size

    def gaps(self):
        out, a, n = [], 0, len(self.mem)
        while a < n:
            if a in self.covered:
                a += 1
                continue
            b = a
            while b < n and b not in self.covered:
                b += 1
            out.append((a, b - 1))
            a = b
        return out

if __name__ == "__main__":
    t = Trace(load())
    print("instructions %d, code bytes %d of %d" % (len(t.starts), len(t.covered), len(t.mem)))
    for a, b in t.gaps():
        print("  gap $%04X-$%04X (%d)" % (a, b, b - a + 1))
    for a, why in t.bad:
        print("  bad $%04X: %s" % (a, why))
