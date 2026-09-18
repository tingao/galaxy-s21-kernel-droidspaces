# extras: optional device helpers

These are **not part of the kernel**. They are root-side scripts that were written while tuning this
device, included because they are useful and because two of them are referenced from the variant
READMEs. None of them are required for the kernel to work.

Install any of them by copying to `/data/adb/service.d/` on a **KernelSU** build (variants 2 or 3) and
rebooting. Remove by deleting the file and rebooting.

| file | what it does | referenced by |
|---|---|---|
| `97-o1q-performance.sh` | The performance profile: re-asserts maximum CPU/GPU clocks while the die is cool, stands down above a ceiling. **This is the thing that makes variant 3 fast**. The kernel change alone barely matters. | [variant 3](../variants/03-ksu-perf.md) |
| `60-battery-limit.sh` | Charge limit using the same mechanism Samsung's own "Battery protection" uses (`batt_full_capacity`), with a watchdog that re-asserts it. | not required by any variant |
| `battery-limit` | CLI front-end: `battery-limit 40` sets a 40 % cap, `battery-limit` prints state. | companion to the above |

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
