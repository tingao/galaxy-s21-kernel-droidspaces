#!/system/bin/sh
# ---------------------------------------------------------------------------
# Battery charge limit for o1q (SM-G9910 / Galaxy S21)
#
# Uses the SAME mechanism Samsung's own "Battery protection" uses:
#   /sys/class/power_supply/battery/batt_full_capacity
# The charger driver (sec_battery.c) votes VOTER_FULL_CAPACITY once
# capacity >= this value and stops charging.  No daemon has to toggle the
# charger on/off, so there is no charge/discharge cycling.
#
# Config : /data/adb/battery-limit.conf      (LIMIT=<0-100>, 100 = no limit)
# Log    : /data/adb/battery-limit.log
# Remove : delete this file (and the conf) and reboot
# ---------------------------------------------------------------------------
CONF=/data/adb/battery-limit.conf
NODE=/sys/class/power_supply/battery/batt_full_capacity
LOG=/data/adb/battery-limit.log

[ -f "$CONF" ] && . "$CONF"
LIMIT="${LIMIT:-40}"

log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

# wait for the battery node to appear
i=0
while [ ! -e "$NODE" ] && [ "$i" -lt 90 ]; do sleep 2; i=$((i+1)); done
if [ ! -e "$NODE" ]; then log "FATAL: $NODE never appeared"; exit 1; fi

log "service start (pid $$), configured LIMIT=$LIMIT"

while :; do
  cur=$(cat "$NODE" 2>/dev/null)
  if [ "$cur" != "$LIMIT" ]; then
    echo "$LIMIT" > "$NODE" 2>/dev/null
    now=$(cat "$NODE" 2>/dev/null)
    log "set batt_full_capacity: was '$cur' -> now '$now' (target $LIMIT)"
  fi
  sleep 60
done
