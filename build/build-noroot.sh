#!/bin/bash
# ---------------------------------------------------------------------------
# VARIANT 1: NO KernelSU, NO root.
#
# Same base as the working v10/v12 kernel (Samsung RKP/KDP disabled -> no silent
# freezes, kABI preserved, container-friendly config) but with KernelSU entirely
# absent:
#   * no drivers/kernelsu
#   * no manual-hook insertions in fs/*, kernel/reboot.c, drivers/input/input.c
#   * stock include/linux/seccomp.h  (the genksyms guard is only needed because
#     KernelSU's Kbuild injects atomic_t filter_count; without KSU there is
#     nothing to guard)
# ---------------------------------------------------------------------------
set -uo pipefail
KROOT=/root/kernel-S21-rewrite
TC=/root/toolchain
export PATH="$TC/clang-r383902b/bin:$PATH"
export ARCH=arm64
cd "$KROOT"

echo "=== 1. reset every file we or KernelSU ever touched ==="
git checkout -- kernel/module.c kernel/Makefile include/linux/sched.h \
                include/linux/sched/user.h kernel/cgroup/cgroup.c \
                arch/arm64/configs/vendor/o1q_chn_hkx_defconfig \
                fs/exec.c fs/open.c fs/read_write.c fs/stat.c kernel/reboot.c \
                drivers/input/input.c drivers/Kconfig drivers/Makefile \
                fs/namespace.c fs/internal.h include/linux/seccomp.h \
                security/selinux/hooks.c security/selinux/selinuxfs.c \
                security/selinux/xfrm.c security/selinux/include/objsec.h
rm -f arch/arm64/configs/stock_defconfig
rm -f drivers/kernelsu
git status --short | grep -vE '^\?\?' || echo "  (clean)"

echo "=== 2. kABI patches ==="
python3 /root/apply_patches.py

echo "=== 3. mandatory GKI patch: cgroup file prefix ==="
patch -p1 < /root/02-cgroup-prefix.patch
echo "  cgroup patch markers: $(grep -c 'kernfs_create_link(cgrp->kn, name, kn)' kernel/cgroup/cgroup.c)"

echo "=== 4. stock_defconfig for /proc/config.gz ==="
python3 - <<'EOS'
import subprocess
p = "kernel/Makefile"
src = open(p, encoding="utf-8").read()
old = '$(obj)/config_data: $(KCONFIG_CONFIG) FORCE'
new = '$(obj)/config_data: arch/arm64/configs/stock_defconfig FORCE'
assert src.count(old) == 1, "config_data rule not found"
open(p, "w", encoding="utf-8").write(src.replace(old, new))
pristine = subprocess.run(
    ["git", "show", "HEAD:arch/arm64/configs/vendor/o1q_chn_hkx_defconfig"],
    capture_output=True, text=True, check=True).stdout
open("arch/arm64/configs/stock_defconfig", "w", encoding="utf-8").write(pristine)
print("  ok")
EOS

echo "=== 5. NO KernelSU (deliberately skipped: ksu-setup.sh, apply_ksu_hooks.py, fix_seccomp_kabi.py) ==="

echo "=== 6. config ==="
DEF=arch/arm64/configs/vendor/o1q_chn_hkx_defconfig
for s in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS DEVTMPFS NETFILTER_XT_MATCH_ADDRTYPE \
         USER_NS NETFILTER_XT_TARGET_LOG NETFILTER_XT_MATCH_RECENT \
         IP_SET IP_SET_HASH_IP IP_SET_HASH_NET NETFILTER_XT_SET \
         TMPFS_POSIX_ACL TMPFS_XATTR; do
  scripts/config --file "$DEF" -e "$s"
done
for s in CGROUP_DEVICE CGROUP_PIDS CGROUP_NET_CLASSID NET_CLS_CGROUP SECURITY_DEFEX PROCA FIVE KSU KSU_MANUAL_HOOK KSU_KPROBES_HOOK KSU_DEBUG; do
  scripts/config --file "$DEF" -d "$s" 2>/dev/null || true
done

echo "=== 7. Samsung hypervisor protection off (the v7 freeze fix, retained) ==="
for s in FASTUH_RKP FASTUH_KDP KDP_TEST RKP_TEST; do
  scripts/config --file "$DEF" -d "$s"; echo "  disabled $s"
done

COMMON=(O="$KROOT/out" ARCH=arm64 LLVM=1
  CROSS_COMPILE="$TC/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
  CLANG_TRIPLE=aarch64-linux-gnu- DTC_EXT="$KROOT/tools/dtc"
  CONFIG_BUILD_ARM64_DT_OVERLAY=y)
make "${COMMON[@]}" vendor/o1q_chn_hkx_defconfig olddefconfig >/tmp/noroot-gen.log 2>&1
echo "configgen rc=$?"

echo "=== 8. VERIFY config ==="
mkdir -p /root/build-logs
for s in KSU KSU_MANUAL_HOOK FASTUH_RKP FASTUH_KDP SECURITY_DEFEX PROCA FIVE \
         SYSVIPC USER_NS IPC_NS PID_NS; do
  printf "  %-20s %s\n" "$s" "$(grep -m1 -E "^#? ?CONFIG_${s}=" out/.config || echo ABSENT)"
done
echo "  --- KernelSU must be completely absent ---"
echo "  CONFIG_KSU lines in config : $(grep -c CONFIG_KSU out/.config)"
echo "  drivers/kernelsu present   : $([ -e drivers/kernelsu ] && echo YES || echo no)"
echo "  ksu hooks in fs/exec.c     : $(grep -c ksu_handle_execveat fs/exec.c)"
cp -f out/.config /root/build-logs/noroot.config

echo "=== 9. clean build ==="
rm -rf out
./build.sh noroot
echo "BUILD_EXIT=$?"
