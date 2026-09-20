# Keeping the phone awake, so the container and its tunnel survive

**Symptom.** The tunnel and anything served from this handset disappear "after a while" and come back
the moment somebody touches the screen. Nothing has crashed: `docker ps` is still healthy once you get
back in, and the container never restarted.

**Cause.** This handset suspends constantly, and its Broadcom Wi-Fi driver cannot enter suspend cleanly.
`dmesg` shows the sequence on every sleep attempt:

```
dhd_set_suspend: force extra Suspend setting
dhd_set_suspend_bcn_li_dtim set lpas failed -23
```

The radio stops passing traffic. While suspended the container is frozen too, so a Cloudflare connector
cannot keep its QUIC heartbeats alive: all four connections expire and every published hostname answers
Cloudflare **`1033`** ("Argo Tunnel error") until the screen is touched. A Droidspaces container does not
cause this and cannot fix it from inside — the suspend decision belongs to the kernel.

**Fix.** Hold a kernel wakeup source, so the kernel never suspends:

```sh
echo dsh-keepawake > /sys/power/wake_lock      # hold
echo dsh-keepawake > /sys/power/wake_unlock    # release
```

`extras/98-keep-awake.sh` does exactly that at boot. Copy it to `/data/adb/service.d/` (KernelSU-Next and
Magisk both execute that directory as root at boot) and reboot.

> The lock is **not** tied to the writing process: the script exits immediately and the wakeup source
> stays active until the name is written to `wake_unlock`. That is why a one-shot boot script is enough.

## Verify it is really holding

```sh
su -c 'cat /sys/power/wake_lock'                 # expect: dsh-keepawake
su -c 'dmesg | grep -c "PM: suspend entry"'      # should stop growing
```

A suspended kernel cannot run your sampler, so a **gap** in samples taken over time is the proof.
Measured on this device: after the lock was in place, 20 minutes on battery with the screen off produced
zero suspend entries and zero sampling gaps, with the connector holding all four connections — where the
same window used to contain several-minute freezes.

## Costs and caveats

* Standby drain rises from roughly zero (suspended) to about **1–3 %/h**. Free on the cable; it turns
  "days" into "hours" unplugged, which is why the script holds unconditionally here.
* Temperatures sit a few degrees higher, since the SoC no longer idles in suspend.
* Revert: delete the script and reboot, or `su -c 'echo dsh-keepawake > /sys/power/wake_unlock'` for an
  immediate release.

## Two things this is often confused with

* **The battery percentage is not evidence of anything.** This device runs ACC (Advanced Charging
  Controller) holding the pack in a fixed band, so the gauge sits still whether the phone slept or not.
  Judge by the log gap.
* **`usb/online=0` with `status=Discharging` is normal** when ACC is pausing charge inside its band. It
  does not mean the cable is data-only or the charger is dead.

## Related: debloating

`extras/debloat-apply.sh` with `extras/debloat-list.txt` disables the stores, software updater,
Bixby/AI/AR, games, DeX, telemetry and preloaded Facebook/Microsoft apps on a headless device. It uses
`pm disable-user` (reversible, and it cannot strip a component the device needs to boot), writes a
rollback script first, and restricts GMS/GSF/Play background activity instead of disabling them, because
stock One UI expects them present.
