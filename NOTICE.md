# NOTICE: third-party components and the proprietary boundary

## What this repository contains

* Build scripts, patches, defconfig and documentation authored for this project, **GPLv2**
  (see [LICENSE](LICENSE)).
* Prebuilt kernel boot images built from those sources and from Samsung's published GPL kernel
  source.

## What this repository does NOT contain

| component | why |
|---|---|
| Samsung's kernel source tree | obtain it yourself, see [SOURCE.md](SOURCE.md) |
| Stock vendor kernel modules (`/vendor/lib/modules/*.ko`) | proprietary. Also unnecessary: the kABI is preserved so the modules already on your phone keep working |
| Firmware blobs (`/vendor/firmware*`) | proprietary |
| Samsung userspace of any kind | proprietary |
| AOSP toolchain binaries | large; obtain from AOSP or your distro |

**No vendor module, firmware blob or Samsung application is redistributed here.**

## The ramdisk caveat

Each published `boot-o1q-*.img` is `kernel + ramdisk`. The kernel is GPLv2 code this project built.
The **ramdisk is Samsung's stock ramdisk**, taken unmodified from the device's original `boot`
partition, and it is proprietary. It is included so the images are ready to flash.

* For **personal use** this is no different from flashing a Samsung update.
* For **redistribution**, this project cannot grant you rights to Samsung's ramdisk. If that matters
  to you, build the image from your own stock firmware with `build/repack.sh`, which produces an
  equivalent result without moving anything proprietary between machines.

## Third-party projects

| project | used for | licence |
|---|---|---|
| [Linux kernel](https://kernel.org) | the kernel itself | GPLv2 |
| [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) | root solution, **legacy** branch (variants 2 and 3) | GPLv2 |
| [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) | the container runtime this kernel is tuned and tested for | see project |
| [Magisk](https://github.com/topjohnwu/Magisk) `magiskboot` | used at build time to unpack/repack boot images | GPLv2 |
| AOSP `clang` + `aarch64-linux-android-4.9` binutils | toolchain | Apache-2.0 with LLVM exceptions / GPL |

KernelSU-Next, Droidspaces and Magisk are **not bundled**. The build scripts fetch or expect them
separately.

## Trademarks

"Samsung", "Galaxy" and "Snapdragon" are trademarks of their respective owners. This is an
independent community project and is not affiliated with, endorsed by, or supported by Samsung
Electronics or Qualcomm.

## No warranty

These images modify your device's kernel. They are provided as-is, with no warranty of any kind.
You are responsible for backing up your device. See the licence for the full disclaimer.
