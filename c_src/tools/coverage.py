#!/usr/bin/env python3
"""Report which routines of the listing the lockstep scenarios executed.

tests\\lockstep.exe --coverage FILE marks every ROM address the real ROM
executed an instruction at (run_tests.bat accumulates all scenarios into
tests\\coverage.bin).  Since every event of those runs was compared, a routine
that was executed was also verified against the C port.

    python tools/coverage.py [tests/coverage.bin]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CSRC = os.path.normpath(os.path.join(HERE, ".."))
ROOT = os.path.normpath(os.path.join(CSRC, ".."))
sys.path.insert(0, os.path.join(ROOT, "disasm"))
import notes, trace          # the disassembler's tracer: where the instructions are


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(CSRC, "tests", "coverage.bin")
    if not os.path.exists(path):
        sys.exit("coverage: missing %s (run run_tests.bat)" % path)
    cov = open(path, "rb").read()
    mem = trace.load()
    tr = trace.Trace(mem, notes.extra_entries(mem))
    refs = json.load(open(os.path.join(ROOT, "disasm", "build", "program_refs.json")))
    labels = {int(a, 16): n for a, n in refs["labels"].items()}
    routines = sorted(int(a, 16) for a in refs["routines"] if int(a, 16) in tr.starts)

    starts = sorted(tr.starts)
    done = sum(1 for a in starts if cov[a])
    print("instructions executed : %d of %d (%.1f%%)" % (done, len(starts), 100.0 * done / len(starts)))
    reached = [a for a in routines if cov[a]]
    print("routines entered      : %d of %d" % (len(reached), len(routines)))
    for a in routines:
        if not cov[a]:
            print("   not entered: %-22s $%04X" % (labels[a], a))
    # instructions never executed inside routines that were entered
    partial = []
    for i, a in enumerate(routines):
        if not cov[a]:
            continue
        end = routines[i + 1] if i + 1 < len(routines) else len(mem)
        miss = [x for x in starts if a <= x < end and not cov[x]]
        if miss:
            partial.append((labels[a], a, len(miss), miss[0]))
    if partial:
        print("entered, with instructions never executed:")
        for name, a, n, first in partial:
            print("   %-22s $%04X  %3d instructions, first $%04X" % (name, a, n, first))


if __name__ == "__main__":
    main()
