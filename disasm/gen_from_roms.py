#!/usr/bin/env python3
"""Rebuild the Clowns CPU image from a ROM set and regenerate + verify the listings.

ROMs are matched by size and CRC32, not by file name, so a MAME `clowns.zip`, a
directory holding it, or a directory of loose files all work.

    h2.cpu  $0000-$03FF     e2.cpu  $0C00-$0FFF
    g2.cpu  $0400-$07FF     d2.cpu  $1000-$13FF
    f2.cpu  $0800-$0BFF     c2.cpu  $1400-$17FF

Usage:
    python gen_from_roms.py [ROMDIR-or-ZIP] [--image-only]

Default ROM location: ../roms.  Steps:
  1. build build/clowns_cpu.bin (the 6K image every tool reads)
  2. emit.py          -> clowns_program_rom.asm
  3. emit_defines.py  -> clowns_defines.asm
  4. verify.py        - must print MISMATCHES : 0
  5. emit_sprites.py  -> sprites_preview.html
A failing step is reported with '!!' and the chain continues; exit status 1 if any failed.
"""
import argparse, glob, os, subprocess, sys, zipfile, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
BUILD = os.path.join(HERE, "build")
IMAGE = os.path.join(BUILD, "clowns_cpu.bin")

# MAME 'clowns' (rev. 2): socket -> (load address, size, crc32)
ROMS = {
    "h2": (0x0000, 0x400, 0xff4432eb), "g2": (0x0400, 0x400, 0x676c934b),
    "f2": (0x0800, 0x400, 0x00757962), "e2": (0x0C00, 0x400, 0x9e506a36),
    "d2": (0x1000, 0x400, 0xd61b5b47), "c2": (0x1400, 0x400, 0x154d129a),
}
ROM_SIZE = 0x1800

def candidates(path):
    """Yield (label, bytes) for every 1K file reachable from path (dir, zip or file)."""
    paths = []
    if os.path.isdir(path):
        paths = [p for p in sorted(glob.glob(os.path.join(path, "*"))) if os.path.isfile(p)]
    else:
        paths.append(path)
    for p in paths:
        if p.lower().endswith(".zip"):
            with zipfile.ZipFile(p) as zf:
                for info in zf.infolist():
                    if info.file_size == 0x400:
                        yield "%s:%s" % (os.path.basename(p), info.filename), zf.read(info)
        elif os.path.getsize(p) == 0x400:
            yield os.path.basename(p), open(p, "rb").read()

def build_image(path):
    by_crc = {crc: sock for sock, (_, _, crc) in ROMS.items()}
    found = {}
    for label, data in candidates(path):
        sock = by_crc.get(zlib.crc32(data) & 0xFFFFFFFF)
        if sock and sock not in found:
            found[sock] = (label, data)
    if len(found) != len(ROMS):
        print("!! no complete 'clowns' (rev. 2) set found under %s (matched: %s)"
              % (path, ", ".join(sorted(found)) or "none"))
        return False
    img = bytearray(ROM_SIZE)
    print("ROM set clowns (rev. 2):")
    for sock, (a, n, crc) in sorted(ROMS.items(), key=lambda kv: kv[1][0]):
        img[a:a + n] = found[sock][1]
        print("  %s  $%04X-$%04X  crc %08x  %s" % (sock, a, a + n - 1, crc, found[sock][0]))
    old = open(IMAGE, "rb").read() if os.path.exists(IMAGE) else None
    os.makedirs(BUILD, exist_ok=True)
    with open(IMAGE, "wb") as fp:
        fp.write(img)
    print("wrote %s%s" % (os.path.relpath(IMAGE, ROOT),
                          "" if old is None else (" (unchanged)" if old == bytes(img) else " (CHANGED)")))
    return True

def run(script, *args):
    print("\n== %s %s" % (script, " ".join(args)))
    sys.stdout.flush()
    r = subprocess.run([sys.executable, os.path.join(HERE, script)] + list(args), cwd=HERE)
    if r.returncode != 0:
        print("!! %s failed (exit %d)" % (script, r.returncode))
    return r.returncode == 0

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("roms", nargs="?", default=os.path.join(ROOT, "roms"),
                    help="ROM directory, set zip or loose file directory (default ../roms)")
    ap.add_argument("--image-only", action="store_true", help="only build the 6K image")
    a = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(line_buffering=True)
    if not os.path.exists(a.roms):
        sys.exit("ROM path %s does not exist" % a.roms)
    if not build_image(os.path.abspath(a.roms)):
        sys.exit(1)
    if a.image_only:
        return
    ok = True
    for script in ("emit.py", "emit_defines.py", "verify.py", "emit_sprites.py"):
        if os.path.exists(os.path.join(HERE, script)):
            ok &= run(script)
        else:
            print("\n(%s not present - skipped)" % script)
    print("\n%s" % ("all steps passed" if ok else "!! some steps failed; see the !! lines above"))
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
