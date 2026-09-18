#!/bin/bash
# v12 = v10 (currently flashed, known good) + KernelSU-Next "legacy" branch HEAD
#
# Why: v10 carries KernelSU-Next v3.2.0-legacy (rev-list 2979, KSU_VERSION 33129).
# The legacy branch is now at rev-list 2993 (KSU_VERSION 33143) and adds, among others:
#   53791c92 manager: throne_tracker: fix ABBA deadlock with packages.list rename
#            -> throne_tracker is what sets ksu_manager_appid; if it deadlocks,
#               is_manager() is false and the manager app is never recognised
#               (=> "Unsupported | Not integrated", no Superuser tab)
#   uapi v2: KERNEL_SU_UAPI_VERSION 2 + do_get_info_legacy + cmd.uapi_version
#            -> what manager v3.3.0 (33214) needs; its absence is why manager 3.3.0
#               on v10 produced "ksu ioctl: unsupported command 0x4b15"
#   14 commits total incl. allowlist strscpy_pad fallback, sucompat __init fix,
#   selinux_hide, adb_root, sulog (replaces tiny_sulog)
#
# Unchanged on purpose (one variable at a time):
#   * Samsung FASTUH_RKP + FASTUH_KDP stay DISABLED (the historic freeze fix)
#   * SECURITY_DEFEX / PROCA / FIVE stay DISABLED exactly as in the working v10
#     (v11 re-enabled them for the fingerprint A/B; that is NOT part of this change)
#   * struct seccomp genksyms guard still needed - klegacy Kbuild line 196 patches
#     the same field, and fix_seccomp_kabi.py pre-applies it under __GENKSYMS__
set -uo pipefail
KROOT=/root/kernel-S21-rewrite
TC=/root/toolchain
export PATH="$TC/clang-r383902b/bin:$PATH"
export ARCH=arm64
cd "$KROOT"

echo "=== 0. pin KernelSU-Next to legacy branch HEAD ==="
git -C /root/KernelSU-Next checkout -f klegacy
git -C /root/KernelSU-Next log --oneline -1
RV=$(git -C /root/KernelSU-Next rev-list --count HEAD)
echo "  rev-list=$RV  ->  KSU_VERSION=$((30000 + RV + 150))"

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
git status --short | grep -vE "^\?\?" || echo "  (clean)"

echo "=== 2. kABI patches (001 = 3_4_5 variant, 002 adapted) ==="
python3 /root/apply_patches.py

echo "=== 3. mandatory GKI patch: cgroup file prefix handling ==="
patch -p1 < /root/02-cgroup-prefix.patch
grep -c "kernfs_create_link(cgrp->kn, name, kn)" kernel/cgroup/cgroup.c

echo "=== 4. stock_defconfig for /proc/config.gz (patch 011) ==="
python3 - <<'EOS'
import subprocess
p="kernel/Makefile"
src=open(p,encoding="utf-8").read()
old='$(obj)/config_data: $(KCONFIG_CONFIG) FORCE'
new='$(obj)/config_data: arch/arm64/configs/stock_defconfig FORCE'
assert src.count(old)==1
open(p,"w",encoding="utf-8").write(src.replace(old,new))
pristine=subprocess.run(["git","show","HEAD:arch/arm64/configs/vendor/o1q_chn_hkx_defconfig"],
    capture_output=True,text=True,check=True).stdout
open("arch/arm64/configs/stock_defconfig","w",encoding="utf-8").write(pristine)
print("  ok")
EOS

echo "=== 4b. genksyms-safe struct seccomp (restore frozen kABI) ==="
python3 /root/fix_seccomp_kabi.py

echo "=== 5. KernelSU-Next wiring + manual hooks ==="
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
echo "=== 7. Samsung hypervisor protection off (v7 change, retained) ==="
for s in FASTUH_RKP FASTUH_KDP KDP_TEST RKP_TEST; do
  scripts/config --file "$DEF" -d "$s"; echo "  disabled $s"
done
echo "=== 8. KernelSU config ==="
scripts/config --file "$DEF" -e KSU
scripts/config --file "$DEF" -e KSU_MANUAL_HOOK
scripts/config --file "$DEF" -d KSU_KPROBES_HOOK
scripts/config --file "$DEF" -d KSU_DEBUG
scripts/config --file "$DEF" -d KSU_DISABLE_MANAGER
scripts/config --file "$DEF" -d KSU_DISABLE_POLICY

COMMON=(O="$KROOT/out" ARCH=arm64 LLVM=1
  CROSS_COMPILE="$TC/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
  CLANG_TRIPLE=aarch64-linux-gnu- DTC_EXT="$KROOT/tools/dtc"
  CONFIG_BUILD_ARM64_DT_OVERLAY=y)
make "${COMMON[@]}" vendor/o1q_chn_hkx_defconfig olddefconfig >/tmp/v12gen.log 2>&1
echo "configgen rc=$?"

echo "=== 9. VERIFY config took ==="
for s in KSU KSU_MANUAL_HOOK KSU_KPROBES_HOOK KSU_DEBUG KSU_DISABLE_MANAGER \
         FASTUH FASTUH_RKP FASTUH_KDP SECURITY_DEFEX PROCA FIVE SYSVIPC USER_NS IPC_NS PID_NS; do
  printf "  %-22s %s\n" "$s" "$(grep -m1 -E "^#? ?CONFIG_${s}=" out/.config || echo ABSENT)"
done
mkdir -p /root/build-logs
cp -f out/.config /root/build-logs/v12.config

echo "=== 10. clean build ==="
rm -rf out
./build.sh v12
echo "BUILD_EXIT=$?"
