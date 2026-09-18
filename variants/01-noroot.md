# Variant 1: no KernelSU, no root

**Image:** `boot-o1q-noroot.img`
**md5:** `33756448f7aa7fb3eb37a6764d5d2382`
**Size:** 100,663,296 bytes (exactly the `boot` partition size)

Same kernel base as the other variants with KernelSU removed completely: no driver, no manual hooks,
no in-kernel root path at all.

## Read this first

**This variant cannot run Droidspaces, Docker, or anything else that needs root.** Droidspaces
requires a root shell to create containers. If you are here for containers, use
[variant 2](02-ksu.md) or [variant 3](03-ksu-perf.md).

Variant 1 is for people who want the kernel's stability fixes and container configuration without any
root surface on the device.

## What is in it

| | |
|---|---|
| Kernel | 5.4.274-qgki, built from Samsung's `SM-G9910` source |
| KernelSU | absent. `CONFIG_KSU` is not set and `drivers/kernelsu` is not present |
| Root | none |
| Clocks | stock Samsung (no governor, thermal or frequency change) |
| Ramdisk | stock, Magisk-free |

### Changes relative to Samsung stock

1. **`FASTUH_RKP` and `FASTUH_KDP` disabled.** Samsung's Realtime Kernel Protection and Kernel Data
   Protection enforce integrity from EL2 and will silently kill a kernel whose image does not match
   what the bootloader expects. No panic, no log, it just dies. `FASTUH` itself remains enabled.
2. **GKI cgroup file-prefix patch.** Required for correct cgroup file naming on this QGKI kernel.
   Without it cgroup v2 consumers misbehave.
3. **Container configuration.** Namespaces and IPC features enabled, legacy cgroup controllers
   disabled:
   * enabled: `SYSVIPC`, `POSIX_MQUEUE`, `IPC_NS`, `PID_NS`, `USER_NS`, `DEVTMPFS`,
     `NETFILTER_XT_MATCH_ADDRTYPE`, `NETFILTER_XT_TARGET_LOG`, `NETFILTER_XT_MATCH_RECENT`,
     `IP_SET`, `IP_SET_HASH_IP`, `IP_SET_HASH_NET`, `NETFILTER_XT_SET`, `TMPFS_POSIX_ACL`,
     `TMPFS_XATTR`
   * disabled: `CGROUP_DEVICE`, `CGROUP_PIDS`, `CGROUP_NET_CLASSID`, `NET_CLS_CGROUP`,
     `SECURITY_DEFEX`, `PROCA`, `FIVE`
4. **`/proc/config.gz` reflects Samsung's pristine config** instead of the built one, so
   configuration checks against the stock baseline stay meaningful.

### What is deliberately NOT changed

* No clock, voltage or thermal-table edits of any kind.
* Kernel thermal trip points left exactly stock (`cpu-0-0-step` 110 °C, `cpu-1-7-step` 108 °C,
  `gpuss-0-step` 95 °C).

## Verification performed

```
CRC gate vs stock symbol set : 0 CRC changes, 0 symbols lost, 0 added   (kABI preserved)
KernelSU symbols in Image    : ksu_handle_execveat 0, ksu_handle_sys_reboot 0,
                               ksu_selinux_hide_init 0, ksu_input_hook 0
Ramdisk magisk/ksu traces    : 0
Config                       : CONFIG_KSU lines = 0, drivers/kernelsu absent
```

Because the kABI is byte-identical to stock, the stock vendor modules load unchanged, so Wi-Fi,
audio, camera and sensors keep working. See the
[modem-module note](../docs/PERFORMANCE.md#a-note-on-module-version-disagreements) for the one
Qualcomm exception present on this device independently of these builds.

> **Boot testing status:** this image has been built and statically verified (CRC gate, symbol
> absence, config) but has **not** been test-flashed on hardware. It is the same base as the two
> variants that have been, with KernelSU removed.

## Flashing

See [../FLASHING.md](../FLASHING.md). Back up your `boot` partition first.

## Building

```sh
cd build && ./build-noroot.sh
```

Requires Samsung's source, see [../SOURCE.md](../SOURCE.md).

## Reverting

Flash back your stock `boot` image backup, or a stock AP file for your build number via Odin. This
variant modifies nothing outside the `boot` partition.
