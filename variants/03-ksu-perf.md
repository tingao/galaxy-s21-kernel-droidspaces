# Variant 3: KernelSU plus performance profile

**Image:** `boot-o1q-ksu-perf.img`
**md5:** `a6b57c54ef68a10775dfa26b48755fde`
**Size:** 100,663,296 bytes

[Variant 2](02-ksu.md) plus the changes needed to recover the sustained performance this device
throws away. No clock or voltage is changed anywhere.

## It is not an overclock

A "performance variant" would normally mean raising clock ceilings. On this SoC that is not possible
from kernel source, and pretending otherwise would just produce an unstable image.

**CPU frequencies are firmware-burned.** The driver is `qcom-cpufreq-hw` (EPSS/OSM), and it builds its
table by *reading the hardware LUT registers*:

```c
static int qcom_cpufreq_hw_read_lut(struct platform_device *pdev, struct cpufreq_qcom *c, u32 max_cores)
{
        for (i = 0; i < lut_max_entries; i++) {
                data = readl_relaxed(c->base + offsets[REG_FREQ_LUT] + i * lut_row_size);
                ...
                dev_pm_opp_add(cpu_dev, freq * 1000, volt);   /* OPPs come FROM the LUT */
        }
}
```

The device tree node `qcom,cpufreq-hw-epss` carries **no OPP table**, only `reg-names`. Those
frequencies are written into the LUT by the bootloader. Adding `opp-hz` entries in the kernel DT
would do nothing.

**The GPU table does not come from this kernel either.** `lahaina-gpu.dtsi` in the source has only 6
levels up to 710 MHz, while the device runs **10 levels up to 840 MHz**. With
`CONFIG_BUILD_ARM64_DT_OVERLAY` unset the boot image carries **no DTB at all**, so the live table
comes from the stock **`dtbo`** partition (`qcom,gpu-pwrlevel-bins`). Raising it means patching and
flashing `dtbo`, which this project deliberately does not do.

## One thing that surprised us

**`CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y` is already in Samsung's pristine defconfig**, line 563
of `arch/arm64/configs/vendor/o1q_chn_hkx_defconfig`. Setting it in a custom kernel is a **no-op**.
The device still runs `schedutil` because userspace overrides the kernel default at boot.

An earlier draft of this variant did set that option, and would have shipped a kernel identical to
variant 2 while claiming a performance change. It does not do that anymore.

## Where the performance actually goes

The limit is not the clock ceiling, it is who is allowed to use it. Measured over a full stress
campaign:

| observation | value |
|---|---|
| in-kernel `step_wise` cooling devices | **`cur_state 0` for the entire campaign**, the kernel never throttled |
| in-kernel trip points | `cpu-0-0-step` 110 °C, `cpu-1-7-step` 108 °C, `gpuss-0-step` 95 °C |
| actual peak temperatures reached | CPU ~65 °C, GPU ~79 °C, nowhere near any trip point |
| **GPU clock under sustained load** | **840 → 443 MHz, 52.7 % of commanded** |
| **prime core under sustained load** | **~57 % of its commanded clock** |

The kernel's own limits never engaged. The throttling is done in **user space**: `thermal-engine` and
`vendor.samsung.hardware.thermal@1.0-service` watch the `*_usr` thermal zones (`trip 125 °C`,
notify-only, a dummy threshold) and write `scaling_max_freq` **down themselves**, early and
aggressively.

## What this variant changes

### 1. Kernel: `core_ctl` starts disabled

```c
kernel/sched/walt/core_ctl.c:
-   cluster->enable = true;
+   cluster->enable = false;
```

Qualcomm's `core_ctl` dynamically isolates cores under low load. We measured it isolating **cpu4 and
cpu7** on this device. Disabling it freed both, and a pinned prime-core benchmark gained **+3.1 %**
with an identical checksum. Defaulting it off means those cores are available from boot instead of
only after a root script runs. The sysfs attribute still lets userspace turn it back on at runtime.

This is the only kernel-level lever available that is both real and safe. The big win is elsewhere.

### 2. User space: the profile (`extras/97-o1q-performance.sh`)

**This is where the gain is, and it is why this variant ships a script as well as a kernel.** It is a
KernelSU service script that:

* re-asserts `scaling_max_freq = cpuinfo_max_freq` on all three clusters, undoing thermal-engine's
  early caps;
* sets the `performance` governor on every cluster;
* holds the GPU ceiling open (`max_pwrlevel 0`, so the full 840 MHz is always permitted) under the
  `msm-adreno-tz` scaling governor, and leaves the floor at the stock default, so the GPU still idles
  down to 315 MHz when nothing wants it. It is allowed to go fast, not forced to stay there;
* **stands down above a configurable ceiling** (default 85 °C), at which point Samsung's
  thermal-engine and the in-kernel limits take back over exactly as stock.

```sh
# install (KernelSU)
cp extras/97-o1q-performance.sh /data/adb/service.d/
chmod 755 /data/adb/service.d/97-o1q-performance.sh
# optional tuning
echo 'CEIL=85000 ABORT=95000' > /data/adb/o1q-perf.conf
reboot
```

Remove it with `rm /data/adb/service.d/97-o1q-performance.sh` and reboot.

### 3. Deliberately NOT changed

* **Kernel thermal trip points are left exactly stock.** Those sysfs files *are* writable
  (`CONFIG_THERMAL_WRITABLE_TRIPS=y`, files `rw-r--r-- root`) and raising them is the obvious "easy"
  trick, but that removes the last hardware safety net and risks permanent SoC damage. Not done, and
  not recommended.
* No voltages, no PLL configuration, no `dtbo` flashing, no CPU/GPU clock tables.

## What you should expect

* **Sustained** performance improves, because the clock stops being taken away. Burst performance is
  roughly unchanged, it was never throttled.
* **The device runs hotter** and the battery drains faster. That is the trade.
* **Battery longevity is affected.** Sustained cycling at higher temperature is the main ageing
  factor for a Li-ion cell, which pulls directly against using a charge limit (40 % for example) for
  longevity. Pick your priority.
* Thermals stay *bounded*: user space backs off above 85 °C, and the untouched in-kernel limits still
  clamp at 108-110 °C (CPU) and 95 °C (GPU).

## Verification status

**Flashed and boot-verified on hardware**, this exact image, md5 `a6b57c54ef68a10775dfa26b48755fde`:

| check | result |
|---|---|
| boots | yes |
| **`core_ctl` at boot** | **`enable=0` on cpu0/cpu4/cpu7, `core_ctl_isolated` empty, measured with *no* boot script active**, so this is the kernel default and not a user-space setting |
| KernelSU | `Kernel Version: 33193`; `su -c id` → `uid=0(root)`, `context=u:r:ksu:s0` |
| Manager | v3.3.0 recognised the kernel (kernel log: `install fd for manager`, `allow root for: 10298`) |
| **Container stack** | Droidspaces container starts, **Docker works inside it**: Server 26.1.5, overlay2, cgroup v2, `docker run --rm hello-world` OK |
| Stability | 0 oops, 0 WARNING, 0 BUG; SELinux Enforcing |
| Vendor modules | 54 stock modules load (see the [modem-module note](../docs/PERFORMANCE.md#a-note-on-module-version-disagreements)) |
| kABI | CRC gate: 0 changes, 0 symbols lost, 0 added |
| rollback | previous image backed up and md5-verified **before** writing; write read-back verified |

* The throttling analysis above is measured, with raw samples and logs.
* **The performance profile script itself has not been soak-tested.** The kernel boots and behaves,
  but the profile's thermal behaviour under a long sustained load is untested. Treat it as
  experimental and watch your temperatures the first time you use it.

## Flashing

See [../FLASHING.md](../FLASHING.md), then install the profile as shown above.

## Building

```sh
cd build && ./build-ksu-perf.sh
```
