# Flashing

**These images replace your kernel. Get it wrong and the phone will not boot.** Read this whole page
before you start. Everything here touches **only** the `boot` partition. Nothing else on your device
is modified, and every step has a rollback.

## Before you begin

| requirement | how to check |
|---|---|
| Bootloader unlocked | `adb shell getprop ro.boot.verifiedbootstate` → `orange` |
| `vbmeta` verification disabled | flashing a custom `boot` will not boot otherwise |
| Root shell available | required for the `dd` route only; use Odin if you have none |
| **A backup of your current `boot` partition** | see below, do this first |

Confirm you have the right device. Everything here is for **SM-G9910 / `o1q`** only:

```sh
adb shell getprop ro.product.device      # o1q
adb shell getprop ro.product.model       # SM-G9910
```

Do **not** flash these on `SM-G991B`, `SM-G996`, `SM-G998` or any Exynos S21. They are different
silicon and different kernel trees.

## Step 0: back up your current boot partition

From a root shell on the device:

```sh
su -c 'dd if=/dev/block/by-name/boot of=/sdcard/boot-backup-$(date +%s).img'
su -c 'md5sum /sdcard/boot-backup-*.img'
```

Pull it somewhere safe. This file is your undo button for everything below.

The partition is 100,663,296 bytes (96 MiB) on this device. Every image published here is exactly
that size. If yours is not, stop.

## Route A: `dd` (no PC needed beyond adb)

```sh
adb push boot-o1q-ksu.img /data/local/tmp/new-boot.img
adb shell
su
# verify the push actually completed before writing anything
md5sum /data/local/tmp/new-boot.img        # compare with the published md5

dd if=/data/local/tmp/new-boot.img of=/dev/block/by-name/boot bs=4096 conv=fsync
sync

# read-back verify, this is the step that catches a bad flash
dd if=/dev/block/by-name/boot of=/data/local/tmp/readback.img bs=4096 count=24576
md5sum /data/local/tmp/readback.img        # must equal the published md5
```

Only reboot once the read-back md5 matches. If it does not, re-flash your Step 0 backup
immediately.

## Route B: Odin

Use the provided `AP-boot-o1q-*.tar.md5` in Odin's **AP** slot. Nothing else needs a slot; leave
`BL`, `CP`, `CSC` and `USERDATA` empty. Do not tick "Re-Partition".

Odin will validate the md5 itself and refuse a corrupt file.

## After flashing

* First boot takes noticeably longer than usual. Give it a few minutes.
* **Variants 2 and 3:** open the KernelSU-Next manager (**v3.3.0 / 33214 or newer**) and confirm the
  home screen reports the kernel instead of *"Unsupported | Not integrated"*. Nothing is granted root
  by default, you choose which apps get it.
* **Variant 3:** the performance profile is a separate opt-in script, see
  [variants/03-ksu-perf.md](variants/03-ksu-perf.md).

## If something goes wrong

| symptom | what to do |
|---|---|
| Boot loop | kernel **safe mode**: hold **volume-down ×3** during boot (variants 2 and 3) |
| Still looping | reflash your Step 0 backup via `dd` or Odin download mode |
| No root after flashing variant 2 or 3 | you flashed variant 1, or the manager is too old |
| Manager says "Not integrated" | update the manager to v3.3.0 (33214) or newer |
| Wi-Fi, cellular or audio dead | the vendor modules failed to load, meaning you flashed an image built against a different source revision. Restore your backup. |

## Safety notes

* **`dtbo` is never touched by anything in this repository.** If you are following advice elsewhere
  that patches the GPU power levels, that means flashing `dtbo`, a different and riskier procedure
  that this project does not use.
* **Variant 3 runs the device hotter on purpose.** Watch your temperatures the first time. If you
  also use a charge limit for battery longevity, understand that these two goals pull in opposite
  directions.
* Flashing a custom kernel can trip Knox-dependent features (Samsung Pay, Secure Folder, some banking
  apps). That is true of any custom kernel on this device and is not specific to these images.
* Keep your Step 0 backup until you are sure you are happy.
