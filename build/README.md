# Building

Three build scripts, one per variant:

| script | variant | produces |
|---|---|---|
| `build-noroot.sh` | 1, no KernelSU | `out/arch/arm64/boot/Image` |
| `build-ksu.sh` | 2, KernelSU | same |
| `build-ksu-perf.sh` | 3, KernelSU plus performance | same |

Then `pack-variant.sh` turns an `Image` into a flashable boot image.

## What you need

1. **Samsung's kernel source for SM-G9910**, see [../SOURCE.md](../SOURCE.md).
2. **The AOSP clang toolchain**: `clang-r383902b` (clang 11.0.2) plus
   `aarch64-linux-android-4.9` binutils.
3. **KernelSU-Next** checked out at the **legacy** branch (variants 2 and 3 only).
4. **`magiskboot`** (from Magisk) for packing, `pack-variant.sh` calls it.
5. A Linux host (tested on WSL2/Ubuntu).

## Expected layout

The scripts are the ones actually used to produce the published images, so they expect the layout
they were written for:

```
/root/kernel-S21-rewrite/     <- Samsung source + our patches applied
/root/toolchain/
    clang-r383902b/
    aarch64-linux-android-4.9/
/root/KernelSU-Next/          <- legacy branch (variants 2 and 3)
/root/build.sh                <- kernel-build.sh from this directory
```

If your paths differ, either create that layout or change the four path variables at the top of each
script:

```sh
KROOT=/root/kernel-S21-rewrite
TC=/root/toolchain
KSU=/root/KernelSU-Next
```

One-liner to relocate them to your own checkout:

```sh
sed -i "s|/root/kernel-S21-rewrite|$PWD/kernel|g; s|/root/toolchain|$PWD/toolchain|g; \
        s|/root/KernelSU-Next|$PWD/KernelSU-Next|g; s|/root/build-logs|$PWD/build-logs|g" \
    build-*.sh pack-variant.sh kernel-build.sh
```

## What a build does

Every script follows the same shape, so the variants differ only where they are meant to:

1. **Reset every file we or KernelSU ever touch** back to pristine before starting. This is what
   makes the builds reproducible: no stale hooks leaking between variants.
2. **Apply the kABI patches** (`apply_patches.py`) and the **GKI cgroup file-prefix patch**.
3. **Point `/proc/config.gz` at Samsung's pristine config**, so config comparisons against stock
   stay meaningful.
4. *(variants 2 and 3)* **`fix_seccomp_kabi.py`**, pre-applies KernelSU's `struct seccomp` field under
   `#ifndef __GENKSYMS__` so exported symbol CRCs do not move.
5. *(variants 2 and 3)* **`ksu-setup.sh` + `apply_ksu_hooks.py`**, wire in KernelSU and place the 13
   manual-hook insertions.
6. **Set the configuration**, then build clean (`rm -rf out`).

## Patches

Two kinds of change, deliberately kept separate. See **[patches/README.md](patches/README.md)** for
what each does and why:

* `patches/02-cgroup-prefix.patch`, a real `patch -p1` diff (GKI cgroup file naming).
* The **kABI patches** in `apply_patches.py`. These are not `.patch` files, because each must land in
  exactly one place and the script aborts if it does not. They move the new `SYSVIPC` /
  `POSIX_MQUEUE` fields into Android's reserved kABI slots so exported symbol CRCs do not move.

## Verifying a build before you flash it

```sh
python3 crcgate.py <stock>.symvers out/Module.symvers
```

You want:

```
CRC CHANGES ON PRE-EXISTING SYMBOLS: 0
SYMBOLS LOST FROM MODIFIED BUILD:    0
NEW EXPORTED SYMBOLS:                0
VERDICT: kABI PRESERVED
```

**If this reports any change, do not flash.** A moved CRC means the 54 prebuilt vendor modules in
`/vendor/lib/modules` will refuse to load and you lose Wi-Fi, cellular and audio. This gate is the
single most important check in the project.

Get `<stock>.symvers` from a build of the unmodified Samsung source, or from a known-good build of
ours.

## Packing

```sh
./pack-variant.sh <label> <path-to-Image> <output-name>
# e.g.
./pack-variant.sh ksu out/arch/arm64/boot/Image boot-o1q-ksu.img
```

It repacks your `Image` into a Magisk-free stock ramdisk donor, checks the result is exactly
100,663,296 bytes, prints the md5, and emits an Odin `AP-*.tar.md5`.

Set `DONOR` to your own stock `boot.img` instead of using someone else's ramdisk if you intend to
redistribute:

```sh
DONOR=/path/to/your-stock-boot.img ./pack-variant.sh ksu out/arch/arm64/boot/Image boot-o1q-ksu.img
```

See [../SOURCE.md](../SOURCE.md), *The ramdisk problem*.

## Notes and gotchas

* **Do not build the three variants in parallel.** They share one source tree and reset each other's
  files. Run them sequentially, and pack the `Image` immediately after each build, because the next
  build deletes `out/`.
* **The boot image carries no DTB.** `CONFIG_BUILD_ARM64_DT_OVERLAY` is unset; the device tree comes
  from the stock `dtbo` partition, which none of this touches.
* **KernelSU-Next must be on the `legacy` branch.** The scripts check it out as `klegacy`. On
  `stable`/`dev` the manual-hook Kconfig option no longer exists and the build will not integrate.
* Expected build time is roughly 10 to 20 minutes per variant on a modest machine.
