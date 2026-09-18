import sys

def parse_symvers(path):
    syms, mods = {}, {}
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) < 3:
            continue
        crc, name, module = f[0], f[1], f[2]
        exp = f[3] if len(f) > 3 else ""
        syms[name] = crc
        mods[name] = (module, exp)
    return syms, mods

B, Bm = parse_symvers(sys.argv[1])
M, Mm = parse_symvers(sys.argv[2])

common = sorted(set(B) & set(M))
only_b = sorted(set(B) - set(M))
only_m = sorted(set(M) - set(B))
crc_diff = [s for s in common if B[s] != M[s]]
exp_diff = [s for s in common if Bm[s][1] != Mm[s][1]]

print("baseline symbols: %d" % len(B))
print("modified symbols: %d" % len(M))
print("common:           %d" % len(common))
print("only in baseline: %d  (LOST)" % len(only_b))
print("only in modified: %d  (new)" % len(only_m))
print("")
print("=" * 72)
print("*** CRC CHANGES ON PRE-EXISTING SYMBOLS: %d ***" % len(crc_diff))
print("=" * 72)
if crc_diff:
    for s in crc_diff[:100]:
        print("  %s" % s)
        print("      %s -> %s   [%s]" % (B[s], M[s], Bm[s][0]))
    if len(crc_diff) > 100:
        print("  ... and %d more" % (len(crc_diff) - 100))
else:
    print("  NONE  <-- kABI preserved")
print("")
print("=" * 72)
print("EXPORT-TYPE CHANGES: %d" % len(exp_diff))
print("=" * 72)
for s in exp_diff[:40]:
    print("  %s: %s -> %s" % (s, Bm[s][1], Mm[s][1]))
if not exp_diff:
    print("  (none)")
print("")
print("=" * 72)
print("SYMBOLS LOST FROM MODIFIED BUILD: %d" % len(only_b))
print("=" * 72)
if only_b:
    for s in only_b[:80]:
        print("  %-46s crc=%s [%s] mod=%s" % (s, B[s], Bm[s][1], Bm[s][0]))
    if len(only_b) > 80:
        print("  ... and %d more" % (len(only_b) - 80))
else:
    print("  (none)")
print("")
print("=" * 72)
print("NEW EXPORTED SYMBOLS: %d" % len(only_m))
print("=" * 72)
for s in only_m[:100]:
    print("  %-46s crc=%s [%s]" % (s, M[s], Mm[s][1]))
if len(only_m) > 100:
    print("  ... and %d more" % (len(only_m) - 100))
print("")
print("=" * 72)
if crc_diff or only_b:
    print("VERDICT: *** kABI NOT PRESERVED - DO NOT FLASH ***")
    sys.exit(1)
print("VERDICT: kABI PRESERVED - zero CRC changes, zero lost symbols")
sys.exit(0)