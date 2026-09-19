# Where the source comes from, and what we redistribute

## Short version

This repository contains **changes to the kernel only**. The Linux kernel base is Samsung's own published
source, which you obtain from Samsung. We do not mirror it here.

```sh
# 1. get Samsung's source for this exact device
#    https://opensource.samsung.com/  ->  search "SM-G9910"
#    (see "Exact base" below for the version to pick)

# 2. apply our delta
cd <samsung-source>
git init && git add -A && git commit -m "samsung stock"
for p in ../build/patches/*.patch; do git apply "$p"; done

# 3. build
cd build && ./build-ksu.sh
```

---

## The licences in play

| component | licence | redistributable? |
|---|---|---|
| Linux kernel source | **GPLv2** | **yes**, with source + licence + notices |
| Samsung's additions to the kernel tree | **GPLv2** (they are in-tree) | yes, same terms |
| Our patches, scripts, defconfig, READMEs | **GPLv2** | yes |
| AOSP `clang` prebuilt toolchain | Apache-2.0 with LLVM exceptions | yes |
| **Stock vendor kernel modules** (`/vendor/lib/modules/*.ko`) | proprietary | **NO** |
| **Firmware blobs** (`/vendor/firmware*`) | proprietary | **NO** |
| **Samsung's ramdisk** (`init`, `dpolicy`, … inside `boot.img`) | proprietary | **legally grey, see below** |
| The rest of `/vendor` and Samsung's userspace | proprietary | **NO** |

Nothing in the "NO" rows is included in this repository. **We never redistribute vendor modules or
firmware**, and you don't need them: the whole point of the CRC gate is that the modules already on
your phone keep working unchanged.

## Why we don't mirror the Samsung kernel tree

It is not a legal requirement to avoid it. GPLv2 source *may* be redistributed. The reasons are
practical and hygiene, not prohibition:

1. **Size.** The tree is multiple gigabytes with history. A repo whose point is three flashable
   images does not need it.
2. **Licence hygiene.** Samsung's drop is not one licence. It contains in-tree code under other
   terms (dual BSD/GPL drivers, third-party and vendor code, some files with additional notices).
   Mirroring it means carrying and maintaining every one of those notices correctly.
3. **Freshness.** Samsung revises its drops. Our patches are written against a *specific* revision
   (below). Pinning the base by reference, not by mirror, keeps the provenance unambiguous.
4. **It is trivially available.** Samsung publishes it publicly for exactly this purpose. Linking to
   it costs a user one download.

**If you do want a full-source fork**, fork Samsung's tree and add our patches. That is a valid
approach and keeps the GPL obligations straightforward. This repo deliberately takes the other route.

## GPLv2 compliance for the prebuilt images

This ships GPLv2 **binaries** (`boot-o1q-*.img`). GPLv2 requires that recipients can get the
corresponding source. That obligation is met by:

* publishing our complete delta as patches in [`build/patches/`](build/patches/), and
* documenting the exact base revision so the corresponding source is reproducible
  (see *Exact base* and *Verifying* below).

If you redistribute these images, keep this repository (or an equivalent offer of the source)
reachable. That is the deal the GPL asks for.

## Exact base

| | |
|---|---|
| Device | `SM-G9910` / `o1q` (Galaxy S21 5G, Snapdragon 888 / SM8350) |
| Samsung build the kernel was validated against | `G9910ZHSFHYL1` / `AP3A.240905.015.A2` |
| Kernel version string | `5.4.274-qgki` |
| Where to get it | Samsung Open Source Release Center → <https://opensource.samsung.com/> → search `SM-G9910` |

Pick the drop matching your device's build number (Settings → About phone → Software information →
Build number). A drop from a nearby revision usually applies; a distant one may not.

## Verifying you have the right base

The patches apply cleanly only to the matching base. After applying them, the build scripts report
the config and the CRC gate. The check that matters:

```sh
python3 build/crcgate.py <stock>.symvers <built>.symvers
# expects:  0 CRC changes on pre-existing symbols, 0 lost, 0 new
```

If the CRC gate reports changes, **your base revision differs from ours** and the kernel will break
stock vendor modules. Do not flash it.

## The ramdisk problem

Read this if you plan to redistribute images.

A boot image is `kernel + ramdisk`. Our `kernel` is GPLv2 code we built. The **ramdisk is Samsung's**.
It is the stock `init`, `dpolicy` and friends, taken unmodified from the device's original partition.

* **For personal use**, flashing the provided image is no different from flashing a Samsung OTA.
* **For redistribution**, the ramdisk is proprietary Samsung userspace and we cannot grant you any
  rights to it. Most custom-kernel projects ignore this. We would rather you knew.

**Clean alternative: build the boot image from your own stock firmware.**

```sh
./build/repack.sh /path/to/your-stock-boot.img \
                  out/arch/arm64/boot/Image \
                  boot-mine.img
```

This takes *your* ramdisk and swaps in *our* kernel. Nothing proprietary moves between machines, and
the result is equivalent to the images published here.

## Not legal advice

This document explains what we do and why. It is not legal advice. If you intend to use this
commercially, to sell devices, ship it in a product, or redistribute at scale, talk to someone
qualified about your GPLv2 source-offer obligations and about Samsung's terms.
