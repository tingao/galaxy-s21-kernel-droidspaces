#!/bin/bash
# ---------------------------------------------------------------------------
# VARIANT 2: KernelSU + PERFORMANCE profile.
#
# Base = the working v12 kernel (KernelSU-Next legacy 33193, kABI preserved),
# changed only in ways that raise sustained performance:
#
#   * CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y
#       - default governor is `performance` instead of `schedutil`, so every
#         cluster requests its maximum clock immediately rather than ramping.
#
# Plus (shipped alongside, installed by the user) a KernelSU service script that
# undoes the aggressive USER-SPACE throttling done by Samsung's thermal-engine:
#   - thermal-engine watches the *_usr thermal zones (trip 125 C, notify-only)
#     and writes scaling_max_freq down itself, long before the kernel's own
#     step_wise limits are anywhere near.
#   - the profile re-asserts maximum clocks while the die is comfortably cool,
#     and stands down when it is not.
#
# NOT changed on purpose:
#   * kernel thermal trip points are left EXACTLY as stock
#       cpu-0-0-step 110 C, cpu-1-7-step 108 C, gpuss-0-step 95 C
#     -> the in-kernel safety net still works even though those files are
#        writable.  Removing it would risk permanent SoC damage.
#   * no clock or voltage table is touched (the CPU LUT is firmware-burned and
#     is not editable from kernel source anyway).
# ---------------------------------------------------------------------------
set -uo pipefail
KROOT=/root/kernel-S21-rewrite
TC=/root/toolchain
export PATH="$TC/clang-r383902b/bin:$PATH"
export ARCH=arm64
cd "$KROOT"

echo "=== 1. reset tracked files to pristine ==="
git checkout -- kernel/module.c kernel/Makefile include/linux/sched.h \
                include/linux/sched/user.h kernel/cgroup/cgroup.c \
                arch/arm64/configs/vendor/o1q_chn_hkx_defconfig \
                fs/exec.c fs/open.c fs/read_write.c fs/stat.c kernel/reboot.c \
                drivers/input/input.c drivers/Kconfig drivers/Makefile \
                fs/namespace.c fs/internal.h include/linux/seccomp.h \
                security/selinux/hooks.c security/selinux/selinuxfs.c \
                security/selinux/xfrm.c security/selinux/include/objsec.h
rm -f arch/arm64/configs/stock_defconfig
git status --short | grep -vE '^\?\?' || echo "  (clean)"

echo "=== 2. kABI patches ==="
python3 /root/apply_patches.py

echo "=== 3. mandatory GKI patch: cgroup file prefix ==="
patch -p1 < /root/02-cgroup-prefix.patch
echo "  markers: $(grep -c 'kernfs_create_link(cgrp->kn, name, kn)' kernel/cgroup/cgroup.c)"

echo "=== 4. stock_defconfig for /proc/config.gz ==="
python3 - <<'EOS'
import subprocess
p = "kernel/Makefile"
src = open(p, encoding="utf-8").read()
old = '$(obj)/config_data: $(KCONFIG_CONFIG) FORCE'
new = '$(obj)/config_data: arch/arm64/configs/stock_defconfig FORCE'
assert src.count(old) == 1
open(p, "w", encoding="utf-8").write(src.replace(old, new))
pristine = subprocess.run(
    ["git", "show", "HEAD:arch/arm64/configs/vendor/o1q_chn_hkx_defconfig"],
    capture_output=True, text=True, check=True).stdout
open("arch/arm64/configs/stock_defconfig", "w", encoding="utf-8").write(pristine)
print("  ok")
EOS

echo "=== 4b. genksyms-safe struct seccomp (KernelSU injects filter_count) ==="
python3 /root/fix_seccomp_kabi.py

echo "=== 5. KernelSU-Next legacy integration + manual hooks ==="
git -C /root/KernelSU-Next checkout -f klegacy
echo "  KernelSU-Next HEAD: $(git -C /root/KernelSU-Next log --oneline -1)"
bash /root/ksu-setup.sh
python3 /root/apply_ksu_hooks.py

echo "=== 6. config ==="
DEF=arch/arm64/configs/vendor/o1q_chn_hkx_defconfig
for s in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS DEVTMPFS NETFILTER_XT_MATCH_ADDRTYPE \
         USER_NS NETFILTER_XT_TARGET_LOG NETFILTER_XT_MATCH_RECENT \
         IP_SET IP_SET_HASH_IP IP_SET_HASH_NET NETFILTER_XT_SET \
         TMPFS_POSIX_ACL TMPFS_XATTR; do
  scripts/config --file "$DEF" -e "$s"
done
for s in CGROUP_DEVICE CGROUP_PIDS CGROUP_NET_CLASSID NET_CLS_CGROUP SECURITY_DEFEX PROCA FIVE; do
  scripts/config --file "$DEF" -d "$s"
done

echo "=== 7. Samsung hypervisor protection off (freeze fix) ==="
for s in FASTUH_RKP FASTUH_KDP KDP_TEST RKP_TEST; do
  scripts/config --file "$DEF" -d "$s"
done

echo "=== 8. KernelSU config ==="
scripts/config --file "$DEF" -e KSU
scripts/config --file "$DEF" -e KSU_MANUAL_HOOK
scripts/config --file "$DEF" -d KSU_KPROBES_HOOK
scripts/config --file "$DEF" -d KSU_DEBUG
scripts/config --file "$DEF" -d KSU_DISABLE_MANAGER
scripts/config --file "$DEF" -d KSU_DISABLE_POLICY

echo "=== 8b. PERFORMANCE: default governor = performance ==="
scripts/config --file "$DEF" -e CPU_FREQ_DEFAULT_GOV_PERFORMANCE
scripts/config --file "$DEF" -d CPU_FREQ_DEFAULT_GOV_SCHEDUTIL
scripts/config --file "$DEF" -d CPU_FREQ_DEFAULT_GOV_ONDEMAND

COMMON=(O="$KROOT/out" ARCH=arm64 LLVM=1
  CROSS_COMPILE="$TC/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
  CLANG_TRIPLE=aarch64-linux-gnu- DTC_EXT="$KROOT/tools/dtc"
  CONFIG_BUILD_ARM64_DT_OVERLAY=y)
make "${COMMON[@]}" vendor/o1q_chn_hkx_defconfig olddefconfig >/tmp/perf-gen.log 2>&1
echo "configgen rc=$?"

echo "=== 9. VERIFY config ==="
mkdir -p /root/build-logs
for s in KSU KSU_MANUAL_HOOK KSU_KPROBES_HOOK FASTUH_RKP FASTUH_KDP \
         CPU_FREQ_DEFAULT_GOV_PERFORMANCE CPU_FREQ_DEFAULT_GOV_SCHEDUTIL; do
  printf "  %-34s %s\n" "$s" "$(grep -m1 -E "^#? ?CONFIG_${s}=" out/.config || echo ABSENT)"
done
echo "  --- governor sanity ---"
grep -E "CONFIG_CPU_FREQ_DEFAULT_GOV" out/.config
cp -f out/.config /root/build-logs/perf.config

echo "=== 10. clean build ==="
rm -rf out
./build.sh perf
echo "BUILD_EXIT=$?"
