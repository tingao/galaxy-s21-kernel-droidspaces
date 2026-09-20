# extras: optional device helpers

These are **not part of the kernel**. They are root-side scripts that were written while tuning this
device, included because they are useful and because two of them are referenced from the variant
READMEs. None of them are required for the kernel to work.

Install any of them by copying to `/data/adb/service.d/` on a **KernelSU** build (variants 2 or 3) and
rebooting. Remove by deleting the file and rebooting.

| file | what it does | referenced by |
|---|---|---|
| `97-o1q-performance.sh` | The performance profile: re-asserts maximum CPU clocks and holds the GPU ceiling open while the die is cool, stands down above a ceiling. The GPU is allowed to reach 840 MHz, not forced to stay there. **This is the thing that makes variant 3 fast**. The kernel change alone barely matters. | [variant 3](../variants/03-ksu-perf.md) |
| `60-battery-limit.sh` | Charge limit using the same mechanism Samsung's own "Battery protection" uses (`batt_full_capacity`), with a watchdog that re-asserts it. | not required by any variant |
| `battery-limit` | CLI front-end: `battery-limit 40` sets a 40 % cap, `battery-limit` prints state. | companion to the above |
| `98-keep-awake.sh` | Holds a kernel wakeup source so the handset stops suspending. Without it this device sleeps constantly, its Broadcom Wi-Fi driver fails to enter suspend cleanly (`dhd_set_suspend lpas failed -23`), the radio stops passing traffic, and a container's Cloudflare connector loses all four QUIC connections until somebody touches the screen. Costs ~1–3 %/h of standby drain, free on a charger. | [docs/KEEP-AWAKE.md](../docs/KEEP-AWAKE.md) |
| `debloat-apply.sh` + `debloat-list.txt` | Reversible debloat for a headless device: disables Galaxy Store, the software updater, Bixby/AI/AR, games, DeX, telemetry and the preloaded Facebook/Microsoft apps with `pm disable-user`, writing a rollback script first. Keeps GMS/GSF/Play installed (stock One UI needs them) but removes their background run permission. The list also records what is deliberately **kept**. | [docs/KEEP-AWAKE.md](../docs/KEEP-AWAKE.md) |
| `99-airplane-wifi.sh` | Enables airplane mode and switches Wi-Fi straight back on, removing the idle-but-powered modem (this handset reports no SIM). Self-healing: saves state, waits up to 60 s for association and a ping, and restores the previous state by itself if Wi-Fi does not return — the revert has to be local on a phone nobody is holding. `status` and `off` included. | [docs/KEEP-AWAKE.md](../docs/KEEP-AWAKE.md) |

## Raising the GPU floor for compute workloads (LLM inference, and similar)

The profile holds the GPU **ceiling** open but leaves the floor at stock, so the GPU idles down to
315 MHz. That is the right default for a phone, and the wrong setting for a GPU compute job. Worth
knowing why before you try to run a model on this device.

**Opening the ceiling is not enough to reach 840 MHz.** Measured here under sustained Vulkan load, with
`max_pwrlevel` held at 0 for the whole run:

| | |
|---|---|
| idle | 315 MHz |
| sustained load | **443 MHz**, and it never goes higher |
| throughput at that clock | 215 GFLOPS |

`max_pwrlevel` never moved during that run, so 443 MHz is simply where the `msm-adreno-tz` governor
settles on its own. It does not ask for more even though 840 MHz is permitted. Nothing in the kernel is
capping it, so the ceiling is not the lever.

**To get the GPU high you raise the floor.** Levels are indexed upward from the fastest, so 0 is
840 MHz and 9 is the 315 MHz stock idle floor:

| `min_pwrlevel` | clock | | `min_pwrlevel` | clock |
|---|---|---|---|---|
| 0 | 840 MHz | | 5 | 540 MHz |
| 1 | 778 MHz | | 6 | 491 MHz |
| 2 | 738 MHz | | 7 | 443 MHz |
| 3 | 676 MHz | | 8 | 379 MHz |
| 4 | 608 MHz | | 9 | 315 MHz (stock default) |

Set it through the profile rather than by hand, so it survives a reboot and does not drift:

```sh
# /data/adb/o1q-perf.conf
CEIL=85000
ABORT=95000
GPU_FLOOR=0        # pin the floor at 840 MHz; 5 for 540 MHz, 3 for 676 MHz
```

Then restart the profile, or reboot. Delete the `GPU_FLOOR` line to go back to stock behaviour, which
is the default.

In testing, setting `GPU_FLOOR=0` moved the GPU off the 443 MHz it otherwise settles at, up to
778 MHz, and the floor permits the top 840 MHz level. A pinned floor also measured **318 GFLOPS**
against the **215 GFLOPS** above, though those come from separate runs, so treat the gap as indicative
rather than exact.

The cost is that the floor pins even at idle: the GPU sits at 840 MHz doing nothing, which shows up as
heat and battery drain with no workload to justify it. For a long inference run that is a fair trade.
For daily use it is not, which is why it is left unset by default.

Two things to keep in mind for a real workload:

* The profile's `CEIL`/`ABORT` guard still applies. Above 85 °C it stops forcing and hands control back
  to Samsung's thermal-engine, so a long run will still slow down once the die is properly hot. That is
  deliberate, and it is the only thing standing between this device and a cooked SoC.
* Running the model inside a Droidspaces container uses a different GPU path: Mesa Turnip over
  `/dev/kgsl-3d0` with VirGL off, not the vendor driver. See [variant 2](../variants/02-ksu.md)
  for what that setup needs.

## Why the battery limit is worth knowing about

On this device the charge ceiling is a **kernel node**:

```
/sys/class/power_supply/battery/batt_full_capacity
```

Writing a percentage there makes the charger driver stop charging when capacity reaches it. That is
exactly how Samsung implements Battery protection's 80 % "Maximum" option, and the kernel logs it
plainly:

```
sec_bat_check_full_capacity: full_capacity(80) status(2)
sec_bat_check_full_capacity : stop charging(81, 80, OPTION)
_sec_vote(...): CHGEN (VOTER_CABLE, 2) -> (VOTER_FULL_CAPACITY, 1)
```

This is *better* than the app-style approach of toggling charging on and off, because the battery is
not cycled at the threshold. The charger simply stops and the device runs from the charger. Samsung
only exposes 85/80 in the UI; the node takes any value, so 40 % works.

`60-battery-limit.sh` ships with a watchdog because Samsung's framework rewrites that node when you
toggle Battery protection, which would otherwise silently undo your limit.

> **Note:** a charge limit and the performance profile pull in opposite directions. Keeping a cell at
> 40 % reduces calendar ageing; running it hot every day accelerates it. Pick one priority.

## Caveat

These are the scripts as used on the development device, with paths and assumptions documented in
their headers. They are not packaged, not versioned, and not covered by any support. Read them before
running them. `97-o1q-performance.sh` in particular is designed to make the device run hotter than
stock, and it is the one to remove first if anything misbehaves.
