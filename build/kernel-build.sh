#!/bin/bash
# Reproducible WSL build for SM-G9910 (o1q) QGKI 5.4.274
# Toolchain: AOSP clang-r416183b (Clang 12.0.5) per build.config.common
#            + AOSP GCC 4.9 binutils (aarch64 + arm32)
# Usage: ./build.sh <label> [--noconfig]
set -uo pipefail

KROOT=/root/kernel-S21-rewrite
TC=/root/toolchain
CLANG_BIN=$TC/clang-r383902b/bin
GCC64=$TC/aarch64-linux-android-4.9/bin/aarch64-linux-android-
LOGDIR=/root/build-logs
mkdir -p "$LOGDIR"

LABEL="${1:-build}"
NOCONFIG="${2:-}"
LOG="$LOGDIR/$LABEL.log"
: > "$LOG"

export PATH="$CLANG_BIN:$PATH"
export ARCH=arm64
JOBS=$(nproc)

cd "$KROOT"

COMMON=(
  -j"$JOBS"
  O="$KROOT/out"
  ARCH=arm64
  LLVM=1
  CROSS_COMPILE="$GCC64"
  CLANG_TRIPLE=aarch64-linux-gnu-
  DTC_EXT="$KROOT/tools/dtc"
  CONFIG_BUILD_ARM64_DT_OVERLAY=y
  CONFIG_SECTION_MISMATCH_WARN_ONLY=y
)

log() { echo "$@" | tee -a "$LOG"; }

log "=== [$LABEL] toolchain ==="
{ clang --version | head -1; ld.lld --version | head -1; "${GCC64}as" --version | head -1; } 2>&1 | tee -a "$LOG"

if [ "$NOCONFIG" != "--noconfig" ]; then
  log "=== [$LABEL] defconfig ==="
  make "${COMMON[@]}" vendor/o1q_chn_hkx_defconfig >>"$LOG" 2>&1
  log "defconfig exit=$?"
fi

log "=== [$LABEL] build ==="
make "${COMMON[@]}" >>"$LOG" 2>&1
RC=$?
log "make exit=$RC"

log "=== [$LABEL] artifacts ==="
for f in out/arch/arm64/boot/Image out/vmlinux out/Module.symvers out/System.map out/arch/arm64/boot/Image.gz; do
  if [ -f "$KROOT/$f" ]; then log "OK   $f  ($(stat -c%s "$KROOT/$f") bytes)"; else log "MISS $f"; fi
done
cp -f "$KROOT/out/.config"        "$LOGDIR/$LABEL.config"     2>/dev/null
cp -f "$KROOT/out/Module.symvers" "$LOGDIR/$LABEL.symvers"    2>/dev/null
cp -f "$KROOT/out/System.map"     "$LOGDIR/$LABEL.System.map" 2>/dev/null
log "=== [$LABEL] DONE rc=$RC ==="
exit $RC