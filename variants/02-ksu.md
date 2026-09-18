# Variant 2: KernelSU, stock clocks

**Image:** `boot-o1q-ksu.img`
**md5:** `e21278ddaaf6abc2a14c7e051b263714`
**Size:** 100,663,296 bytes

> This exact image has been flashed and validated on hardware. It is the build all the container,
> root and stability results below were measured on.

The recommended variant. Root via KernelSU-Next, with Samsung's stock clocks and thermals left
completely alone. This is the one to use for Droidspaces and Docker.

## What is in it

| | |
|---|---|
| Kernel | 5.4.274-qgki, built from Samsung's `SM-G9910` source |
| Root | KernelSU-Next legacy, `KSU_VERSION 33193`, UAPI v2, built into the kernel image |
| Hook mode | Manual (source-level hooks), not LKM, not kprobes |
| Clocks | stock: no governor, thermal or frequency change |
| Ramdisk | stock, Magisk-free. KernelSU does not need or ship a patched ramdisk here |

## KernelSU integration notes

* **Legacy branch, deliberately.** KernelSU-Next's `stable` and `dev` branches have removed
  source-level manual-hook integration, and their own Kconfig says the kprobe path *"should not be
  used on kernel below 5.10"*. For a 5.4 non-GKI kernel the legacy branch is the only maintained
  track.
* **Built in, not a module.** No `.ko` is loaded at runtime. KernelSU-Next publishes prebuilt modules
  only for GKI KMIs (`android12-5.10` through `android16-6.12`), so there is no 5.4 build and LKM
  mode is not an option on this device. The manager will not ask for a `.ko` file with this image.
* **Manual hooks** go in `fs/exec.c`, `fs/open.c`, `fs/read_write.c`, `fs/stat.c`, `kernel/reboot.c`
  and `drivers/input/input.c` (13 insertions, see `build/apply_ksu_hooks.py`).
* **kABI kept intact.** KernelSU-Next's Kbuild injects `atomic_t filter_count` into `struct seccomp`,
  which changes the type graph genksyms walks and moves thousands of exported symbol CRCs. Every
  stock vendor module would then refuse to load. `build/fix_seccomp_kabi.py` pre-applies that field
  under `#ifndef __GENKSYMS__`, so genksyms still sees the original layout. On arm64 the field lands
  in existing tail padding: `sizeof(struct seccomp)` stays 16 and `offsetof(filter)` stays 8, so the
  ABI really is unchanged.

### Manager app requirements

Use KernelSU-Next manager v3.3.0 (33214) or newer. With the 33193 kernel you get:

```
Working · BUILT-IN (GKI1) · Version: v3.2.0-legacy (33193-2) · Hook mode: Manual
Superusers 2 · Modules 2 · Manager v3.3.0 (33214-2)
```

Older managers, v3.2.0 / 33129 for example, may report *"Unsupported | Not integrated"*. That is the
app's GKI gate, not a broken kernel. Updating the manager fixes it.

## Verification performed

Measured on a retail SM-G9910 running this exact build:

| | result |
|---|---|
| Kernel interface | `Kernel Version: 33193`, manager APK signature matches the kernel's compiled-in expectation |
| Manager recognised | kernel log: `KernelSU: install fd for manager: <uid>` |
| Root | `su -c id` gives `uid=0(root)`, `context=u:r:ksu:s0` |
| Features | `su_compat`, `kernel_umount`, `avc_spoof` enabled |
| Modules | `ksud module list` OK; droidspaces daemon autostarts |
| Vendor modules | 54 stock vendor modules load, see the [modem-module note](../docs/PERFORMANCE.md#a-note-on-module-version-disagreements) |
| Kernel errors | 0 oops, 0 WARNING, 0 BUG across a full stress campaign |
| SELinux | Enforcing, 0 AVC denials in container operation |
| Docker in Droidspaces | works: Server 26.1.5, overlay2, cgroup v2, `docker run --rm hello-world` rc=0 |
| GPU in container | Adreno 660 via Mesa Turnip (`/dev/kgsl-3d0`), Vulkan 1.3.359, OpenGL 4.6 `FD660` |
| kABI | CRC gate: 0 changes, 0 lost, 0 added |

## Container recipe that was tested

```sh
droidspaces --name=mycontainer start --net=nat --hw-access --gpu --termux-x11 --pulse-audio
```

* `--gpu` with VirGL off. Turnip needs VirGL disabled or the GPU stays unavailable.
* Hardware GL/Vulkan also needs Mesa built for Android containers (Turnip), plus
  `MESA_LOADER_DRIVER_OVERRIDE=kgsl` and `TU_DEBUG=noconform`.
* CLI order matters: options go before the command, `droidspaces --name=X run …`.

## Flashing

See [../FLASHING.md](../FLASHING.md).

Safe mode if something goes wrong: volume-down ×3 during boot. `su` is available to any app you grant
it to in the manager, and nothing is granted by default.

## Building

```sh
cd build && ./build-ksu.sh
```

Requires Samsung's source, see [../SOURCE.md](../SOURCE.md).

## What this variant does not fix

Sustained performance on this device is limited by user-space thermal throttling rather than by the
kernel. The GPU drops from 840 MHz to 443 MHz (52.7 % of commanded) and the prime core averages about
57 % of its commanded clock under sustained load. This kernel behaves the same way, because Samsung's
own thermal-engine is doing the throttling. See [variant 3](03-ksu-perf.md) if you want that relaxed.
