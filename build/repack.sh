#!/bin/bash
# ---------------------------------------------------------------------------
# repack.sh <donor-boot.img> <kernel-Image> <output.img>
#
# Build a boot image from YOUR OWN stock boot.img plus our kernel Image, so
# nothing proprietary moves between machines. This is the redistribution-safe
# path described in ../SOURCE.md.
#
# Why it exists: a boot image is kernel + ramdisk. Our kernel is GPLv2 code we
# built, but the ramdisk is Samsung's proprietary userspace, taken from the
# device's original partition. Repacking your own donor avoids redistributing
# theirs.
#
# Requires magiskboot (from Magisk) on PATH, or set MAGISKBOOT to its path.
# ---------------------------------------------------------------------------
set -e

DONOR="$1"
IMG="$2"
OUT="$3"

if [ -z "$DONOR" ] || [ -z "$IMG" ] || [ -z "$OUT" ]; then
  echo "usage: $0 <donor-boot.img> <kernel-Image> <output.img>"
  echo "  donor-boot.img  your own stock boot image"
  echo "  kernel-Image    out/arch/arm64/boot/Image from a build"
  echo "  output.img      where to write the result"
  exit 1
fi

[ -f "$DONOR" ] || { echo "ABORT: donor not found: $DONOR"; exit 1; }
[ -f "$IMG" ]   || { echo "ABORT: kernel Image not found: $IMG"; exit 1; }

MAGISKBOOT="${MAGISKBOOT:-magiskboot}"
command -v "$MAGISKBOOT" >/dev/null 2>&1 || { echo "ABORT: magiskboot not found, set MAGISKBOOT=/path/to/magiskboot"; exit 1; }

# resolve OUT before we change directory
case "$OUT" in
  /*) : ;;
  *)  OUT="$PWD/$OUT" ;;
esac

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cd "$W"

echo "=== donor ==="
cp -f "$(cd "$(dirname "$DONOR")" && pwd)/$(basename "$DONOR")" boot.img
echo "  $DONOR"
echo "  md5 $(md5sum boot.img | cut -d' ' -f1)"

echo "=== unpack, swap the kernel, repack ==="
"$MAGISKBOOT" unpack boot.img >/dev/null 2>&1
cp -f "$(cd "$(dirname "$IMG")" && pwd)/$(basename "$IMG")" kernel
echo "  kernel $(stat -c%s kernel) bytes, md5 $(md5sum kernel | cut -d' ' -f1)"
"$MAGISKBOOT" repack boot.img >/dev/null 2>&1

[ -f new-boot.img ] || { echo "ABORT: repack produced no image"; exit 1; }
cp -f new-boot.img "$OUT"

echo "=== result ==="
echo "  $OUT"
echo "  size $(stat -c%s "$OUT") bytes"
md5sum "$OUT"
echo "  (the boot partition on this device is 100,663,296 bytes)"
