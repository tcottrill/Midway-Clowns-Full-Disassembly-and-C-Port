"""Generate sprites_preview.html: every bitmap the listing describes, drawn the
way the game's own routines read it (font glyphs, seesaw pictures stored bottom
row first, rider, the 18 clown pictures, the two balloon pictures).

A single self-contained page, no external resources.  It is the semantic check
for the bit pictures in clowns_program_rom.asm: the round trip proves the
bytes, the page shows that rows, widths and bit order are understood.
"""
import html, json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import notes, trace

OUT = os.path.join(HERE, "sprites_preview.html")

def rows_of(mem, a, width, count):
    """count rows of width bytes -> list of '#'/'.' strings, bit 0 leftmost."""
    return ["".join(notes.bits(mem[a + r * width + c]) for c in range(width)) for r in range(count)]

def collect(mem, labels):
    groups = []
    font = []
    for i, ch in enumerate(notes.FONT_CHARS):
        a = notes.FONT_AT + 10 * i
        shown = {"@": "blank", "Q": "Q = Y", "K": "K = arrow"}.get(ch, ch)
        font.append(("%s" % shown, a, rows_of(mem, a, 1, 10)))
    groups.append(("Font ($055E): 34 glyphs, 8 x 10", font))
    seesaw = []
    for i in range(notes.SEESAW_COUNT):
        a = notes.word(mem, notes.SEESAW_PTRS + 2 * i)
        n = mem[a]
        seesaw.append((labels.get(a, "L%04X" % a), a, list(reversed(rows_of(mem, a + 1, 5, n)))))
    groups.append(("Seesaw ($0374): 5 pictures, 40 pixels wide, stored bottom row first", seesaw))
    clowns = [("RiderPicture", 0x0802, rows_of(mem, 0x0802, 1, 15))]
    for i in range(notes.CLOWN_COUNT):
        a = notes.word(mem, notes.CLOWN_PTRS + 2 * i)
        clowns.append(("$%02X %s" % (i, labels.get(a, "L%04X" % a)), a, rows_of(mem, a + 2, mem[a + 1], mem[a])))
    groups.append(("Clowns: the rider ($0802) and the 18 flyer pictures ($0812)", clowns))
    groups.append(("Balloons ($0B93): 8 rows each", [
        ("BalloonRightPic", 0x0B93, rows_of(mem, 0x0B93, 1, 8)),
        ("BalloonLeftPic", 0x0B9B, rows_of(mem, 0x0B9B, 1, 8)),
    ]))
    return groups

PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><title>Clowns bitmaps</title>
<style>
body{background:#000;color:#9f9;font:13px/1.4 monospace;margin:16px}
h3{color:#cfc;font-weight:normal;border-bottom:1px solid #353;padding-bottom:4px}
.s{display:inline-block;margin:6px 10px 10px 0;text-align:center;vertical-align:top}
canvas{background:#000;border:1px solid #242;image-rendering:pixelated}
.d{color:#6a6}
</style></head><body>
<h3>Clowns (Midway, 1978) - bitmaps in the program ROM, %(count)d pictures</h3>
%(body)s
<script>
var S=%(data)s;
var Z=4;
for(var k in S){var c=document.getElementById(k),r=S[k],x=c.getContext('2d');
x.fillStyle='#fff';
for(var j=0;j<r.length;j++)for(var i=0;i<r[j].length;i++)if(r[j][i]=='#')x.fillRect(i*Z,j*Z,Z,Z);}
</script></body></html>
"""

def main():
    mem = trace.load()
    labels = notes.load_notes().labels
    groups = collect(mem, labels)
    body, data, count = [], {}, 0
    for title, items in groups:
        body.append("<h3>%s</h3>" % html.escape(title))
        for name, a, rows in items:
            key = "c%04X" % a
            data[key] = rows
            w, h = max(len(r) for r in rows) * 4, len(rows) * 4
            body.append("<div class='s'><canvas id='%s' width='%d' height='%d'></canvas><br>%s<br>"
                        "<span class='d'>%04X</span></div>" % (key, w, h, html.escape(name), a))
            count += 1
    with open(OUT, "w", newline="\n") as fp:
        fp.write(PAGE % {"count": count, "body": "\n".join(body), "data": json.dumps(data)})
    print("wrote %s (%d pictures)" % (os.path.basename(OUT), count))

if __name__ == "__main__":
    main()
