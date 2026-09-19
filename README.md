# Galaxy S21 kernel with Droidspaces / Docker container support

Custom Linux kernels for the Samsung Galaxy S21 5G (SM-G9910, codename o1q, Snapdragon 888 / SM8350).

The goal was narrow: run containers on bare metal Android. Docker inside
Droidspaces (https://github.com/ravindu644/Droidspaces-OSS) works on this kernel.
`docker run hello-world` returns 0, with overlayfs, cgroup v2 and systemd all live inside the container.

Three variants, differing only in root and performance:

| # | Variant | Root | Clocks | md5 | For |
|---|---|---|---|---|---|
| 1 | `boot-o1q-noroot.img` | none | stock | `33756448f7aa7fb3eb37a6764d5d2382` | stability fixes without root |
| 2 | `boot-o1q-ksu.img` | KernelSU-Next | stock | `e21278ddaaf6abc2a14c7e051b263714` | root, modules, containers, stock thermals |
| 3 | `boot-o1q-ksu-perf.img` | KernelSU-Next | stock silicon, relaxed throttling | `a6b57c54ef68a10775dfa26b48755fde` | maximum sustained performance |

All three are 100,663,296 bytes, which is exactly the boot partition size. Odin packages and full
notes are in [releases/](releases/). Variants 2 and 3 are flashed and validated on real hardware;
variant 1 builds clean and passes static checks.

> Variant 3 is not a clock or voltage overclock. The CPU frequency table on this SoC is burned into
> the EPSS/OSM hardware LUT by the bootloader, so kernel source can't touch it, and the GPU
> power-level table comes from the stock dtbo partition rather than this kernel. What variant 3 does
> instead: core_ctl starts disabled, and a user-space profile stops Samsung's thermal-engine from
> taking your clocks away. Measurements behind that are in
> [variant 3's README](variants/03-ksu-perf.md).

---

## Why this kernel exists

A kernel build for this device does not boot usefully out of the box. Two problems had
to be solved:

1. The SoC dies silently. Samsung's FASTUH RKP (Realtime Kernel Protection) and KDP (Kernel Data
   Protection) enforce credential, namespace and page-table integrity from EL2. An image that does
   not match what Samsung expects gets killed with no panic, no log, no warning. It just stops. Both
   are disabled here. FASTUH itself stays enabled.
2. Stock vendor modules have to keep loading. The phone ships 54 prebuilt kernel modules in
   `/vendor/lib/modules`. Move the CRC of one exported symbol and they refuse to load, and Wi-Fi,
   cellular and audio go with them. Every build here is gated on a CRC check against the stock symbol
   set. Current builds report 0 CRC changes, 0 symbols lost, 0 added.

## What works (measured on a retail SM-G9910)

| | result |
|---|---|
| Vendor modules | 54 loaded and working; `qmi_helpers` logs `disagrees about version` warnings on some boots (0-8), cause not identified |
| Kernel errors | 0 oops, 0 WARNING, 0 BUG across all stress campaigns |
| SELinux | Enforcing |
| Docker in Droidspaces | working: Server 26.1.5, overlay2, cgroup v2, hello-world OK |
| GPU inside the container | working: Adreno 660 via Mesa Turnip (`/dev/kgsl-3d0`) |
| CPU overhead of containerisation | ~0% (−0.01% / +0.01%, below a 0.05% measurement floor) |
| Disk overhead of containerisation | write −19.5%, fsync +42%, cold read −75% (that's the loop→ext4→f2fs stack, not the CPU) |

Full measurements: [docs/PERFORMANCE.md](docs/PERFORMANCE.md).

---

## Flashing

Read [FLASHING.md](FLASHING.md) first. Short version:

* Unlocked bootloader required, and vbmeta must have verification disabled.
* Only the boot partition is touched. No variant here modifies dtbo.
* Two routes work: dd to `/dev/block/by-name/boot` from a root shell, or Odin with the provided
  `AP-*.tar.md5`.
* Back up your current boot partition first. FLASHING.md has the one-liner.
* If a build misbehaves, KernelSU safe mode is volume-down ×3 during boot (variants 2 and 3).

## Building it yourself

```sh
git clone <this repo>
cd build
./build-ksu.sh          # or build-noroot.sh / build-ksu-perf.sh
```

You supply Samsung's kernel source yourself. [SOURCE.md](SOURCE.md) explains why, and where to get
it. This repository holds only our changes plus the build scripts.

## Kernel details

| | |
|---|---|
| Base | Samsung SM-G9910 / o1q kernel 5.4.274-qgki |
| Architecture | arm64, QGKI, GKI 1.0 kABI/KMI enforcement |
| Toolchain | AOSP clang-r383902b (11.0.2) + aarch64-linux-android-4.9 binutils |
| KernelSU | KernelSU-Next (https://github.com/KernelSU-Next/KernelSU-Next) legacy branch, KSU_VERSION 33193, UAPI v2, built into the kernel image with manual hooks (not LKM, not kprobes) |
| Manager | KernelSU-Next manager v3.3.0 (33214) or newer |
| Container config | SYSVIPC, POSIX_MQUEUE, IPC_NS, PID_NS, USER_NS, NETFILTER_XT_*, IP_SET, TMPFS_POSIX_ACL/XATTR enabled; CGROUP_DEVICE, CGROUP_PIDS, NET_CLS_CGROUP disabled |
| Compressed | no, the kernel is raw in the boot image |

> KernelSU-Next's legacy branch is deliberate. Stable/dev have removed source-level manual-hook
> integration entirely, and upstream calls the kprobe path something that *"should not be used on
> kernel below 5.10"*. The legacy branch is the only maintained track for a 5.4 non-GKI kernel. Its
> +200 version offset gives 30000 + 2993 + 200 = 33193.

## Droidspaces notes

Verified container recipe (Droidspaces v6.5.5):

```sh
droidspaces --name=mycontainer start \
  --net=nat --hw-access --gpu --termux-x11 --pulse-audio
```

* `--gpu` with `--virgl` off is what gets the Adreno path (Turnip) working. Turn VirGL on and the GPU
  becomes unavailable.
* Hardware GL/Vulkan in the container needs Mesa built for Android containers (Turnip), plus
  `MESA_LOADER_DRIVER_OVERRIDE=kgsl` and `TU_DEBUG=noconform`.
* Droidspaces wants options before the command: `droidspaces --name=X run …`.

## Licence

The Linux kernel is GPLv2. Our modifications ship under the same terms, see [LICENSE](LICENSE).
Samsung's proprietary components are not redistributed here. Read [SOURCE.md](SOURCE.md) and
[NOTICE](NOTICE.md) before reusing anything from this repository.

## Credits

* Droidspaces (https://github.com/ravindu644/Droidspaces-OSS) by ravindu644, the container runtime
  this kernel is tuned for.
* KernelSU-Next (https://github.com/KernelSU-Next/KernelSU-Next), root solution (legacy branch).
* Manual-hook layout adapted from ravindu644's scope-minimised manual hooks.
