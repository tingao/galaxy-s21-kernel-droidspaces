# Releases

Three boot images. All are 100,663,296 bytes (exactly the boot partition size), and all use the same
Magisk-free stock ramdisk donor.

| # | file | md5 | Odin tar md5 | hardware verified |
|---|---|---|---|---|
| 1 | `boot-o1q-noroot.img` | `33756448f7aa7fb3eb37a6764d5d2382` | `1dd902387fdf9d60926aa941a99d105a` | built and statically verified, not test-flashed |
| 2 | `boot-o1q-ksu.img` | `e21278ddaaf6abc2a14c7e051b263714` | `fbc2996e72dbc6e9036d48fa9dbe77f1` | yes, flashed and validated |
| 3 | `boot-o1q-ksu-perf.img` | `a6b57c54ef68a10775dfa26b48755fde` | `5cbba0a76e018ca04eabc0ab61784c44` | yes, flashed and boot-verified |

Each image also ships as an Odin package, `AP-boot-o1q-*.tar` + `.tar.md5`. The `.tar.md5` is the tar
bytes with the hash appended; Odin validates it itself.

## Which one do I want?

* Containers (Droidspaces / Docker) → variant 2, and read the
  [container recipe](../variants/02-ksu.md#container-recipe-that-was-tested). Variant 1 has no root,
  so it can't run containers at all.
* Root, stock thermals → variant 2.
* Root, maximum sustained performance, more heat → variant 3.
* No root at all → variant 1.

## Verifying before you flash

Compare the md5 after downloading, and again after pushing to the device:

```sh
md5sum boot-o1q-ksu.img          # must match the table above
adb push boot-o1q-ksu.img /data/local/tmp/new-boot.img
adb shell su -c 'md5sum /data/local/tmp/new-boot.img'
```

A truncated push is the most common cause of a bad flash. Only write to the partition once both
hashes match.

## What was checked on every image

```
size                  == 100,663,296 bytes
CRC gate              == 0 CRC changes, 0 symbols lost, 0 added   (kABI preserved)
vendor module impact  == 54 stock vendor modules load (see the modem-module note in docs/PERFORMANCE.md)
ramdisk               == 0 magisk/ksu traces
```

Variant 1 additionally: `CONFIG_KSU` absent, `drivers/kernelsu` absent, 0 KernelSU symbols in the
image.

Variant 2 additionally, measured on hardware: root, KernelSU manager working, 0 oops / 0 WARNING /
0 BUG, SELinux Enforcing, Docker inside Droidspaces returning rc=0.

## Rolling back

Flash your own boot backup, or a stock AP file for your build number. See
[../FLASHING.md](../FLASHING.md). Nothing in this project touches dtbo, vendor_boot or super.
