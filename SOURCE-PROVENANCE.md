# Where this source came from

This branch is the stock Samsung kernel source for the Galaxy S21 5G
(SM-G9910, codename `o1q`), unmodified. It is the base the published kernels
are built from. The changes that turn it into those kernels are not committed
here; they are applied by the scripts in the `build/` directory of the `main`
branch, which is also where the build instructions live.

## Exact release

* Target build: `G9910ZHSFHYL1` (Android 15, One UI, `AP3A.240905.015.A2`)
* Kernel version: `5.4.274-qgki`, matching the device's `uname -r`
* Defconfig: `arch/arm64/configs/vendor/o1q_chn_hkx_defconfig`

## How this tree was assembled

Downloaded from Samsung Open Source Release Center:

https://opensource.samsung.com/uploadSearch?searchValue=SM-G9910

Two archives, applied in order:

1. `SM-G9910_HKTW_15_Opensource.zip`, the base, version `G9910ZHUBHYD9`
2. `SM-G9910_HKTW_15_Opensource_G9910ZHSFHYL1.zip`, a small delta

```sh
unzip SM-G9910_HKTW_15_Opensource.zip
unzip -o SM-G9910_HKTW_15_Opensource_G9910ZHSFHYL1.zip
```

The tree in this branch is both archives extracted in that order, with the
delta's `Kernel/` prefix stripped so it lands over the base.

## What is not here

* The eight binary firmware files under `firmware/`, see
  [`firmware/where-to-find.md`](firmware/where-to-find.md)
* The AOSP clang toolchain, which is large and available separately

## Licence

GPLv2. See `COPYING`. Retrieved from Samsung Open Source Release Center on
2026-09-17.
