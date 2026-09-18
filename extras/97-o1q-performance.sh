#!/system/bin/sh
# ---------------------------------------------------------------------------
# o1q PERFORMANCE PROFILE  (companion to the "KernelSU + performance" kernel)
#
# WHY THIS EXISTS
#   On this device the sustained clocks are NOT limited by the kernel.  Measured:
#     * kernel step_wise cooling devices sitting at cur_state 0 the whole time
#       (cpu-0-0-step trip 110 C, cpu-1-7-step 108 C, gpuss-0-step 95 C)
#     * yet the GPU throttled 840 -> 443 MHz (52.7% of commanded) and the prime
#       core averaged ~57% of its commanded clock
#   The throttling is done in USER SPACE: `thermal-engine` watches the *_usr
#   thermal zones (trip 125 C, notify-only) and writes scaling_max_freq down
#   itself, long before the kernel's own limits are anywhere near.
#
# WHAT THIS DOES
#   Re-asserts maximum clocks while the die is comfortably cool, and stands down
#   when it is not.  Above CEIL it stops forcing, so Samsung's thermal-engine and
#   the in-kernel step_wise limits take back over exactly as stock.
#
# WHAT THIS DELIBERATELY DOES NOT DO
#   It never touches kernel thermal trip points.  Those files ARE writable
#   (rw-r--r-- root) but raising them would remove the last hardware safety net
#   and risks permanent SoC damage.
#
# INSTALL (KernelSU):  cp to /data/adb/service.d/ then reboot
# REMOVE        :      delete the file and reboot
# CONFIG        :      /data/adb/o1q-perf.conf  ->  CEIL=85000 ABORT=95000
# ---------------------------------------------------------------------------

CONF=/data/adb/o1q-perf.conf
[ -f "$CONF" ] && . "$CONF"
CEIL=${CEIL:-85000}     # stop forcing above this (millidegrees C)
ABORT=${ABORT:-95000}   # above this, do nothing at all
LOG=/data/adb/o1q-perf.log

log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

_zt(){ for d in /sys/class/thermal/thermal_zone*; do
         [ "$(cat $d/type 2>/dev/null)" = "$1" ] && { echo "$d"; return; }; done; }
CPU0=$(_zt cpu-0-0-usr); CPUSS=$(_zt cpuss-0-usr); GPUSS=$(_zt gpuss-0-usr)

# wait for the nodes
i=0
while { [ ! -e "$CPU0" ] || [ ! -d /sys/devices/system/cpu/cpu7/cpufreq ]; } && [ "$i" -lt 90 ]; do
  sleep 2; i=$((i+1))
done
log "start pid=$$ ceil=$CEIL abort=$ABORT sensors: $CPU0 $CPUSS $GPUSS"

hwmax(){ cat /sys/devices/system/cpu/cpu$1/cpufreq/cpuinfo_max_freq 2>/dev/null; }

while :; do
  t0=$(cat "$CPU0/temp" 2>/dev/null)
  ts=$(cat "$CPUSS/temp" 2>/dev/null)
  tg=$(cat "$GPUSS/temp" 2>/dev/null)
  mx=0
  for v in "$t0" "$ts" "$tg"; do
    [ -n "$v" ] && [ "$v" -gt "$mx" ] 2>/dev/null && mx=$v
  done

  if [ "$mx" -ge "$ABORT" ]; then
    sleep 10
    continue
  fi

  if [ "$mx" -lt "$CEIL" ]; then
    for c in 0 4 7; do
      m=$(hwmax "$c")
      [ -z "$m" ] && continue
      cur=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq 2>/dev/null)
      if [ "$cur" != "$m" ]; then
        echo "$m" > /sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq 2>/dev/null
      fi
      echo performance > /sys/devices/system/cpu/cpu$c/cpufreq/scaling_governor 2>/dev/null
    done
    echo 0 > /sys/class/kgsl/kgsl-3d0/min_pwrlevel 2>/dev/null
    echo performance > /sys/class/kgsl/kgsl-3d0/devfreq/governor 2>/dev/null
  fi
  sleep 5
done
