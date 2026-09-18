#!/usr/bin/env python3
# KernelSU-Next's Kbuild appends `atomic_t filter_count;` to struct seccomp, which
# lives inside struct task_struct. That changes the type graph genksyms walks, so
# 9561 of 14520 exported symbol CRCs moved -> every prebuilt stock vendor module
# would refuse to load.
#
# On arm64 `int mode;` (4 bytes) is followed by 4 bytes of tail padding before the
# 8-byte `filter` pointer, so the new 4-byte field lands exactly in that hole:
# sizeof(struct seccomp) stays 16 and offsetof(filter) stays 8.  The layout is
# therefore already ABI-identical - only genksyms needs to be told so.
#
# This is the same technique Android uses for _ANDROID_KABI_REPLACE, which
# collapses to the original field under #ifdef __GENKSYMS__.
#
# We pre-apply the field ourselves (with the guard) so KernelSU's own
# `grep -q "atomic_t filter_count;"` check finds it and skips its sed.
import sys

P = "include/linux/seccomp.h"
s = open(P, encoding="utf-8").read()

old_struct = "struct seccomp {\n\tint mode;\n\tstruct seccomp_filter *filter;\n};"
new_struct = (
    "struct seccomp {\n"
    "\tint mode;\n"
    "#ifndef __GENKSYMS__\n"
    "\t/* KernelSU-Next seccomp filter accounting.  This lands in the 4 bytes\n"
    "\t * of tail padding that follow 'int mode' on 64-bit, so the size of\n"
    "\t * this struct and the offset of @filter are unchanged.  genksyms\n"
    "\t * still sees the original two-field layout, which keeps the frozen\n"
    "\t * Android kABI CRCs intact for the prebuilt vendor modules.\n"
    "\t */\n"
    "\tatomic_t filter_count;\n"
    "#endif\n"
    "\tstruct seccomp_filter *filter;\n"
    "};"
)
if s.count(old_struct) != 1:
    print("  [FAIL] struct seccomp anchor not found (already patched?)"); sys.exit(1)
s = s.replace(old_struct, new_struct)

old_inc = "#include <linux/thread_info.h>\n"
new_inc = ("#include <linux/thread_info.h>\n"
           "#ifndef __GENKSYMS__\n"
           "#include <linux/atomic.h>\n"
           "#endif\n")
if s.count(old_inc) != 1:
    print("  [FAIL] thread_info include anchor not found"); sys.exit(1)
s = s.replace(old_inc, new_inc)

open(P, "w", encoding="utf-8").write(s)
print("  seccomp.h: KSU field present for the compiler, invisible to genksyms")
