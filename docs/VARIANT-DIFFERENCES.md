# What exactly differs between the three variants

Every variant is built from the same base with the same scripts. This page is the precise diff, so you
can judge a variant by its actual changes instead of by a description.

## Summary

| | variant 1 (no root) | variant 2 (KernelSU) | variant 3 (+performance) |
|---|---|---|---|
| `CONFIG_KSU` | **absent entirely** | `=y` + `MANUAL_HOOK=y` | `=y` + `MANUAL_HOOK=y` |
| KernelSU source | not present | integrated | integrated |
| Manual hooks in `fs/*`, `kernel/reboot.c`, `drivers/input/input.c` | **not applied** | applied (13 insertions) | applied |
| `struct seccomp` genksyms guard | **not needed, not applied** | applied | applied |
| `kernel/sched/walt/core_ctl.c` | stock (`enable = true`) | stock (`enable = true`) | **`enable = false`** |
| Container config | yes | yes | yes |
| `FASTUH_RKP` / `FASTUH_KDP` | disabled | disabled | disabled |
| kABI / CRC gate | 0 changes | 0 changes | 0 changes |

## Variant 2 → variant 1 (verified config diff)

```
$ diff <(sort v12.config) <(sort noroot.config)
11 lines differ, and every one of them is KernelSU.
0 lines are unique to variant 1.
```

Specifically, variant 2 has and variant 1 lacks:

```
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y
# CONFIG_KSU_DEBUG is not set
# CONFIG_KSU_DISABLE_MANAGER is not set
# CONFIG_KSU_DISABLE_POLICY is not set
# CONFIG_KSU_ALLOWLIST_WORKAROUND is not set
```

**Variant 1 is variant 2 with KernelSU removed, nothing else.** Its configuration is a strict subset.

Two consequences worth understanding:

* **No `struct seccomp` guard.** `fix_seccomp_kabi.py` exists only because KernelSU-Next's Kbuild injects
  `atomic_t filter_count` into `struct seccomp`, which moves thousands of exported symbol CRCs. With no
  KernelSU there is nothing to guard, so variant 1 leaves `include/linux/seccomp.h` completely stock.
  That is *cleaner*, not a lesser build.
* **No manual hooks.** The 13 insertions in `fs/exec.c`, `fs/open.c`, `fs/read_write.c`, `fs/stat.c`,
  `kernel/reboot.c` and `drivers/input/input.c` exist only to serve KernelSU. Variant 1 does not apply
  them.

## Variant 2 → variant 3 (verified config diff)

```
$ diff v12.config perf.config
(identical)
```

**Variant 3 changes no kernel configuration option at all.** Its entire kernel delta is one line of C:

```diff
--- a/kernel/sched/walt/core_ctl.c
+++ b/kernel/sched/walt/core_ctl.c
@@
-	cluster->enable = true;
+	cluster->enable = false;
```

That is deliberate, and it is the honest outcome of investigating what actually limits performance on
this device. In particular:

* Setting `CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y` would have been a **no-op**. It is already in
  Samsung's pristine defconfig, and the device still runs `schedutil` because userspace overrides the
  kernel default at boot.
* There is no CPU clock table to raise: the EPSS/OSM frequency LUT is written by the bootloader.
* There is no GPU table to raise in this kernel: it comes from the stock `dtbo` partition.

So the remaining kernel-level lever is `core_ctl`, and the rest of variant 3's benefit comes from the
user-space profile in [`extras/97-o1q-performance.sh`](../extras/97-o1q-performance.sh). See
[variant 3's README](../variants/03-ksu-perf.md).

## Shared by all three

Identical across every variant. This is the part that makes the device usable at all:

| change | why |
|---|---|
| `FASTUH_RKP`, `FASTUH_KDP` disabled | Samsung's EL2 integrity enforcement silently kills a kernel whose image does not match; no panic, no log |
| GKI cgroup file-prefix patch | required for correct cgroup file naming on this QGKI kernel |
| container configuration | `SYSVIPC`, `POSIX_MQUEUE`, `IPC_NS`, `PID_NS`, `USER_NS`, `DEVTMPFS`, `NETFILTER_XT_*`, `IP_SET*`, `TMPFS_POSIX_ACL/XATTR` enabled; `CGROUP_DEVICE`, `CGROUP_PIDS`, `NET_CLS_CGROUP` disabled |
| `SECURITY_DEFEX`, `PROCA`, `FIVE` disabled | Samsung process-integrity features; they interfere with the container/root workloads these kernels exist for |
| `/proc/config.gz` pinned to Samsung's config | so config comparisons against stock stay meaningful |
| kABI preserved | CRC gate 0 changes / 0 lost / 0 added on every build, and the stock vendor modules keep loading |

## Reproducing the diffs

```sh
# after building each variant, build.sh leaves a .config in build-logs/
diff <(sort build-logs/v12.config)    <(sort build-logs/noroot.config)
diff    build-logs/v12.config           build-logs/perf.config

# the gate that actually matters
python3 build/crcgate.py <stock>.symvers build-logs/<variant>.symvers
```
