# Measured performance: host vs Droidspaces vs Docker-in-Droidspaces

All figures below were measured on a retail **SM-G9910** running this kernel, with the device cooled
to a fixed gate temperature before each test and the levels interleaved inside each round so thermal
drift hit them equally. Raw logs and samplers are available on request; the methodology is described
per section.

Levels:

| | |
|---|---|
| **L0** | bare Android host, no container |
| **L1** | inside a Droidspaces container |
| **L2** | inside a Docker container running *inside* Droidspaces |

## Headline

| dimension | L0 host | L1 Droidspaces | L2 Docker in Droidspaces |
|---|---|---|---|
| CPU, pinned single core | 395,588,116 ops/s | **−0.01 %** | **+0.01 %** |
| CPU, 8-thread sustained 15 min | 2,142,760,452 ops/s | −1.94 % | −1.77 % |
| Memory bandwidth | ~31 GB/s | −3.0 % (noise) | +1.7 % (noise) |
| Disk write (2 GiB) | 693.9 MB/s | **−19.5 %** | **−19.6 %** |
| Disk fsync (2 GiB) | 132.5 ms | **+41.7 %** | **+42.0 %** |
| Disk cold read (2 GiB) | 2702 MB/s | **−75.2 %** | **−74.6 %** |
| GPU sustained (pinned 840 MHz) | 242.96 GFLOPS | +7.6 % | +1.2 % |
| GPU submission round-trip | 155.1 µs | −0.4 % | −1.8 % |

### The three things worth knowing

1. **CPU and memory cost of the containers is zero.** Droidspaces and Docker are namespace/`chroot`
   sharing, not VMs. There is no instruction emulation and no syscall translation to pay for. The
   measured difference is −0.01 % / +0.01 %, below the ~0.05 % measurement floor.

2. **The real cost is in the storage stack.** The chain is
   `f2fs → loop device → ext4 → overlayfs → docker writable layer`. Writes pay ~20 %, `fsync` pays
   ~42 %, and cold reads pay ~75 % because reads have to be driven down through the loop device.

3. **The containers add no GPU cost.** Both levels reach the same `/dev/kgsl-3d0` through the same
   Mesa Turnip driver. There is no GPU emulation layer to pay for.

## GPU detail

The GPU work is provably identical at all three levels: the **same SPIR-V shader**
(md5 `3700582ed0fdd507553842388efe68e4`) drives a vendor driver at L0 and Mesa Turnip at L1/L2, and
all three return the **same checksum** `12322598.2295`.

| | L0 | L1 | L2 |
|---|---|---|---|
| device | `Adreno (TM) 660` | `Turnip Adreno (TM) 660` | `Turnip Adreno (TM) 660` |
| Vulkan | 1.1.128 (vendor) | 1.3.359 (Mesa) | 1.3.359 (Mesa) |
| sustained, 90 s | 242.96 GFLOPS | 261.33 | 245.81 |
| submission | 155.1 µs | 154.5 µs | 152.4 µs |

> **If you compare these to spec-sheet GFLOPS, note that L0 uses Qualcomm's proprietary driver and
> L1/L2 use Mesa's reverse-engineered Turnip over the same kgsl device.** Any throughput difference
> between L0 and L1 is *driver substitution*, not containerisation.

### Methodology warning: thermal position dominates everything

In an earlier L1-vs-L2 campaign with a **fixed** order (L1 first, L2 second), L2 measured **31 %
slower**, which looked like a container penalty. It was not. Alternating the order per round:

| round | order | L1 | L2 |
|---|---|---|---|
| 1 | L1 first | **357.02** | 241.43 |
| 2 | L2 first | 219.56 | **316.92** |

Whichever level runs **first** from the cooled gate gets ~317-357 GFLOPS; whichever runs **second**
gets ~220-241. With a Latin square across three levels the *winner rotates every round*: L0 wins
round 1, L1 round 2, L2 round 3. That is what "no level effect" looks like.

**The position effect is about −41 %, roughly five times the largest level delta.** Any fixed-order
benchmark on this device is measuring thermals, not containers.

## Throttling

| | |
|---|---|
| GPU, ceiling held open at 840 MHz | settles at **443 MHz, 52.7 % of the permitted clock** |
| GPU throughput, cool-start vs hot-start | 342 → 202 GFLOPS (−41 %) |
| Prime core under sustained load | **~57 % of commanded clock** |
| Sustained vs burst, 8-thread CPU | −21 % |
| peak die temperatures | CPU ~65 °C, GPU ~79 °C, battery ≤37.6 °C |

**The kernel is not what throttles you.** The in-kernel `step_wise` cooling devices
(`cpu-0-0-step` 110 °C, `cpu-1-7-step` 108 °C, `gpuss-0-step` 95 °C) sat at `cur_state 0` for the
entire campaign, so they never engaged. The caps come from **user space**: `thermal-engine` and
`vendor.samsung.hardware.thermal@1.0-service` watch the `*_usr` zones (dummy 125 °C trip) and write
`scaling_max_freq` down themselves, early and aggressively.

The GPU is a separate case with a different mechanism. Holding the ceiling open (`max_pwrlevel 0`)
does **not** get the GPU to 840 MHz: under sustained load it settles at 443 MHz while `max_pwrlevel`
never moves, so that figure is the `msm-adreno-tz` governor's own steady state rather than a thermal
cap. Reaching 840 MHz sustained needs the floor pinned (`min_pwrlevel 0`), which also means the GPU
never idles below 840 MHz.

This is why [variant 3](../variants/03-ksu-perf.md) targets user space instead of clock tables.

## Stability

Across every campaign (CPU soaks, disk soaks, GPU runs, container nesting):

* **0 oops, 0 `WARNING`, 0 `BUG`**
* **54 stock vendor modules load.** One Qualcomm exception, see the note below.
* SELinux **Enforcing**, 0 AVC denials during container operation
* no reboot, no frozen phase, no GPU fault or hang
* ~457 GB written to UFS during disk testing without a single I/O error

### A note on module version disagreements

`qmi_helpers` and `ipa_fwmk` are Qualcomm modem-side modules. On this device they log

```
qmi_helpers: disagrees about version of symbol module_layout
```

and do not appear in `/proc/modules`. Three things worth knowing:

* **The count is not stable.** It varied between boots (8 on one, 4 on another, 0 on a third)
  depending on whether the modem subsystem initialises far enough to request them. Quoting a single
  figure from one `dmesg` snapshot is meaningless. An earlier draft of these docs claimed
  "0 disagreements" purely because the modules had not been requested yet when that snapshot was
  taken. If you see this number, sample it consistently or ignore it.
* **Neither module exists in `/vendor/lib/modules`** on this firmware (97 files there, neither among
  them), and this test device has **no SIM** (`gsm.sim.state: ABSENT,ABSENT`), so that path is never
  exercised.
* **This is not verified against a stock kernel.** It was present across every build made during this
  project (v9, v10 and the current images), so it is not a regression introduced here, but no stock
  kernel was flashed to confirm that it also occurs there. Treat it as an open, documented
  observation instead of a cleared one.

## Reproducing

The benchmark sources, campaign drivers, samplers and analysers used for these numbers live outside
this repository. The essential rules, if you want to reproduce or extend them:

1. Set clocks to a defined state, and **cool to a measured idle baseline before every test**.
2. **Interleave the levels inside each round**, and **alternate the order**, or use a Latin square.
3. For comparable numbers, pin the GPU explicitly (`min_pwrlevel 0`, not just the `performance`
   governor; the governor alone gave 154 GFLOPS vs 318 GFLOPS pinned). That is a measurement choice,
   not the shipped policy: the profile deliberately does not pin, it holds the ceiling open and lets
   the GPU idle down between bursts.
4. Sample `gpuclk` continuously. **`gpu_busy_percentage` reads 0 % under Vulkan compute** on this
   device even at full load, so do not use it as a load signal. `devfreq/cur_freq` is also
   unreliable; read `/sys/class/kgsl/kgsl-3d0/gpuclk`.
5. Use a fixed seed in any checksum, or it is not comparable across machines of different speed.
