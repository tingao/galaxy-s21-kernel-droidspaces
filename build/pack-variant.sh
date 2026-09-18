#!/bin/bash
# pack-variant.sh <label> <kernel-Image-path> <output-image-name>
# Repack a built Image into the Magisk-free stock ramdisk donor.
#
# Set DONOR to your OWN stock boot.img if you intend to publish images. The
# default is the donor used for the releases in this repository; see ../SOURCE.md.
set -e
LABEL="$1"; IMG="$2"; OUTNAME="$3"
DONOR="${DONOR:-/root/out-v10/boot-v10-nomagisk.img}"
MAGISKBOOT="${MAGISKBOOT:-/root/magiskboot}"
W=/root/pack-$LABEL
REL=/root/release

if [ -z "$LABEL" ] || [ -z "$IMG" ] || [ -z "$OUTNAME" ]; then
  echo "usage: $0 <label> <path-to-Image> <output-name>"
  echo "  label        short name, e.g. ksu"
  echo "  Image        out/arch/arm64/boot/Image from a build"
  echo "  output-name  e.g. boot-o1q-ksu.img"
  exit 1
fi
[ -f "$DONOR" ] || { echo "ABORT: donor not found: $DONOR"; exit 1; }
[ -f "$IMG" ]   || { echo "ABORT: kernel Image not found: $IMG"; exit 1; }

mkdir -p "$REL"
rm -rf "$W"; mkdir -p "$W"; cd "$W"

echo "=== donor: Magisk-free stock ramdisk ==="
cp -f "$DONOR" donor.img
echo "  donor: $DONOR"
echo "  donor md5: $(md5sum donor.img | cut -d' ' -f1)"

echo "=== unpack + swap kernel ==="
"$MAGISKBOOT" unpack donor.img >/dev/null 2>&1
cp -f "$IMG" kernel
ls -l kernel

echo "=== repack ==="
rm -f new-boot.img
"$MAGISKBOOT" repack donor.img >/dev/null 2>&1
[ -f new-boot.img ] || { echo "ABORT: repack produced no image"; exit 1; }
SZ=$(stat -c%s new-boot.img)
echo "  size = $SZ (must be 100663296)"
[ "$SZ" = "100663296" ] || { echo "ABORT: unexpected size"; exit 1; }

cp -f new-boot.img "$REL/$OUTNAME"
echo "=== artifact ==="
ls -l "$REL/$OUTNAME"
md5sum "$REL/$OUTNAME"

echo "=== sanity: kernel build time inside the packed image ==="
strings -a kernel | grep -m1 "Linux version" || true

echo "=== Odin tar + self-verifying .tar.md5 ==="
cd "$REL"
cp -f "$OUTNAME" boot.img
TAR="AP-${OUTNAME%.img}.tar"
tar --format=ustar -cf "$TAR" boot.img
rm -f boot.img
cp -f "$TAR" "$TAR.md5"
md5sum "$TAR" >> "$TAR.md5"
TSZ=$(stat -c%s "$TAR")
A=$(md5sum "$TAR" | cut -d' ' -f1)
# Odin appends "<md5>  <name>\n" after the tar bytes. The tar body is binary and
# contains 0x0A, so the trailing text has to be read by offset, not with tail -1.
B=$(tail -c +$((TSZ + 1)) "$TAR.md5" | cut -d' ' -f1)
echo "  odin tar md5 self-check: computed=$A appended=$B"
[ "$A" = "$B" ] && echo "  OK" || { echo "  *** MISMATCH ***"; exit 1; }
ls -l "$REL"
