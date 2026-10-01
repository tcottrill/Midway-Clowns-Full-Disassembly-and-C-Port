"""Intel 8080 opcode table, decoder and encoder (Intel mnemonics).

TAB[opcode] = (mnemonic, operand template, size) for the documented opcodes.
Operand templates are register names with at most one trailing value marker:
    ""        no operand                       RET
    "B"       register / register pair         PUSH B, INR M
    "A,M"     two registers                    MOV A,M
    "@8"      8-bit value                      ANI $80, IN $02
    "@16"     16-bit value (low byte first)    JMP $0018, LDA $2021
    "B,@8"    register + 8-bit value           MVI B,$01
    "H,@16"   register pair + 16-bit value     LXI H,$2000
    "#n"      restart number 0-7               RST 1
The twelve undocumented opcodes ($08 $10 $18 $20 $28 $30 $38 $CB $D9 $DD $ED
$FD) are not in TAB: decode() returns None for them and a listing has to carry
them as .byte.
"""

REG8 = ["B", "C", "D", "E", "H", "L", "M", "A"]
RP = ["B", "D", "H", "SP"]
RP_PUSH = ["B", "D", "H", "PSW"]
CC = ["NZ", "Z", "NC", "C", "PO", "PE", "P", "M"]
ALU = ["ADD", "ADC", "SUB", "SBB", "ANA", "XRA", "ORA", "CMP"]
ALU_IMM = ["ADI", "ACI", "SUI", "SBI", "ANI", "XRI", "ORI", "CPI"]

TAB = {}

def _d(op, mn, tmpl=""):
    size = 1 + (2 if "@16" in tmpl else 1 if "@8" in tmpl else 0)
    assert op not in TAB
    TAB[op] = (mn, tmpl, size)

_d(0x00, "NOP")
for i, rp in enumerate(RP):
    _d(0x01 + 16 * i, "LXI", rp + ",@16")
    _d(0x03 + 16 * i, "INX", rp)
    _d(0x09 + 16 * i, "DAD", rp)
    _d(0x0B + 16 * i, "DCX", rp)
for i, rp in enumerate(["B", "D"]):
    _d(0x02 + 16 * i, "STAX", rp)
    _d(0x0A + 16 * i, "LDAX", rp)
for i, r in enumerate(REG8):
    _d(0x04 + 8 * i, "INR", r)
    _d(0x05 + 8 * i, "DCR", r)
    _d(0x06 + 8 * i, "MVI", r + ",@8")
for op, mn in ((0x07, "RLC"), (0x0F, "RRC"), (0x17, "RAL"), (0x1F, "RAR"),
               (0x27, "DAA"), (0x2F, "CMA"), (0x37, "STC"), (0x3F, "CMC")):
    _d(op, mn)
_d(0x22, "SHLD", "@16")
_d(0x2A, "LHLD", "@16")
_d(0x32, "STA", "@16")
_d(0x3A, "LDA", "@16")
for d, rd in enumerate(REG8):
    for s, rs in enumerate(REG8):
        op = 0x40 + 8 * d + s
        if op == 0x76:
            _d(op, "HLT")
        else:
            _d(op, "MOV", rd + "," + rs)
for i, mn in enumerate(ALU):
    for s, rs in enumerate(REG8):
        _d(0x80 + 8 * i + s, mn, rs)
for i, cc in enumerate(CC):
    _d(0xC0 + 8 * i, "R" + cc)
    _d(0xC2 + 8 * i, "J" + cc, "@16")
    _d(0xC4 + 8 * i, "C" + cc, "@16")
    _d(0xC6 + 8 * i, ALU_IMM[i], "@8")
    _d(0xC7 + 8 * i, "RST", "#%d" % i)
for i, rp in enumerate(RP_PUSH):
    _d(0xC1 + 16 * i, "POP", rp)
    _d(0xC5 + 16 * i, "PUSH", rp)
_d(0xC3, "JMP", "@16")
_d(0xC9, "RET")
_d(0xCD, "CALL", "@16")
_d(0xD3, "OUT", "@8")
_d(0xDB, "IN", "@8")
_d(0xE3, "XTHL")
_d(0xE9, "PCHL")
_d(0xEB, "XCHG")
_d(0xF3, "DI")
_d(0xF9, "SPHL")
_d(0xFB, "EI")
assert len(TAB) == 244

JUMPS = {"JMP"} | {"J" + c for c in CC}
CALLS = {"CALL"} | {"C" + c for c in CC}
RETS = {"RET"} | {"R" + c for c in CC}
# control never continues at the next address after these
STOPS = {"JMP", "RET", "PCHL", "HLT"}
# instructions whose 16-bit operand is a memory address (not an immediate)
MEMREF = {"LDA": "r", "STA": "w", "LHLD": "r", "SHLD": "w"}

# (mnemonic, register part of the template) -> (opcode, value kind)
ENC = {}
for _op, (_mn, _t, _n) in TAB.items():
    _parts = _t.split(",") if _t else []
    _kind = None
    if _parts and _parts[-1] in ("@8", "@16"):
        _kind = _parts.pop()
    ENC[(_mn, ",".join(_parts))] = (_op, _kind)

def decode(mem, a):
    """(mnemonic, template, value, size) for the instruction at mem[a], or None
    for an undocumented opcode or an instruction that runs off the end."""
    e = TAB.get(mem[a])
    if e is None:
        return None
    mn, tmpl, size = e
    if a + size > len(mem):
        return None
    val = None
    if size == 2:
        val = mem[a + 1]
    elif size == 3:
        val = mem[a + 1] | (mem[a + 2] << 8)
    return mn, tmpl, val, size

def encode(mn, regs, value=None):
    """Bytes for mnemonic + register part ("" / "B" / "A,M" / "#1") and the
    value (None when the instruction has none); None when it cannot be encoded."""
    e = ENC.get((mn, regs))
    if e is None:
        return None
    op, kind = e
    if kind is None:
        return [op] if value is None else None
    if value is None:
        return None
    if kind == "@8":
        return [op, value] if 0 <= value <= 0xFF else None
    return [op, value & 0xFF, value >> 8] if 0 <= value <= 0xFFFF else None
