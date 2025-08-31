#!/usr/bin/env bash
# macsos — собрать системную диагностику в архив на Desktop
set -euo pipefail
OUT="$HOME/Desktop/macsos_$(date +%F_%H-%M-%S)"
mkdir -p "$OUT"
exec 3>&1 1>"$OUT/run.log" 2>&1

echo "== basic =="
sw_vers || true
sysctl kern.boottime || true
uptime || true

echo "== hardware =="
system_profiler SPHardwareDataType || true
pmset -g batt || true

echo "== processes =="
top -l 1 -n 0 || true
ps -axo pid,ppid,pcpu,pmem,state,etimes,comm | head -n 200 || true

echo "== memory/disk/io =="
vm_stat || true
df -h || true
iostat -w 1 3 || true

echo "== power/thermal (sudo) =="
if command -v powermetrics >/dev/null; then
  sudo powermetrics --samplers smc -n 1 >"$OUT/powermetrics.txt" 2>/dev/null || true
fi

echo "== network =="
scutil --dns || true
ifconfig || true
route -n get default || true
networkQuality -v >"$OUT/networkQuality.txt" 2>/dev/null || true

echo "== logs last 10m (errors/faults) =="
log show --predicate 'eventType in {"fault","error"}' --last 10m --style syslog >"$OUT/errors_10m.log" 2>/dev/null || true

echo "== spotlight =="
mdutil -sa >"$OUT/spotlight_status.txt" 2>/dev/null || true

echo "== sysdiagnose (sudo, может занять время) =="
if command -v sysdiagnose >/dev/null; then
  sudo sysdiagnose -f "$OUT" >/dev/null 2>&1 || true
fi

cd "$(dirname "$OUT")"
tar -czf "$OUT.tgz" "$(basename "$OUT")" >/dev/null 2>&1 || true
printf "%s\n" "$OUT.tgz" >&3
