#!/usr/bin/env bash
set -euo pipefail

T_SYSINFO=10
T_HW=30
T_VMSTAT=5
T_DF=15
T_IOSTAT=20
T_POWERM=20
T_NETQ=30
T_LOGSHOW=30
T_MDUTIL=10
T_SYSDIAG=300
T_TAR=60

OUT="$HOME/macsos_$(date +%F_%H-%M-%S)"
LOG="$OUT/run.log"
mkdir -p "$OUT"
exec 3>&1 1>"$LOG" 2>&1
START_TS=$(date +%s)

ts(){ date +%H:%M:%S; }
say(){ printf "[%s] %s\n" "$(ts)" "$*" >&3; }

run_step(){
  local label="$1"; local tmax="$2"; shift 2
  say "-> ${label}..."
  ( "$@" ) & local pid=$!
  local i=0; local start now; local sym='|/-\'
  start=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    local c="${sym:$((i%4)):1}"
    printf "\r[%s] %s %s" "$(ts)" "${label}" "$c" >&3
    i=$((i+1))
    sleep 0.2
    now=$(date +%s)
    if (( now - start >= tmax )); then
      printf "\r[%s] %s TIMEOUT, stopping...\n" "$(ts)" "${label}" >&3
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      say "WARN: ${label} timed out after ${tmax}s (see $LOG)"
      return 124
    fi
  done
  local rc=0; wait "$pid" || rc=$?
  printf "\r[%s] %s OK\n" "$(ts)" "${label}" >&3
  (( rc != 0 )) && say "WARN: ${label} exited with code $rc (see $LOG)" || true
  return 0
}

on_err(){
  printf "\n[%s] ERROR. Last log lines:\n" "$(ts)" >&3
  tail -n 40 "$LOG" >&3 || true
}
trap on_err ERR

say "Start. Log: $LOG"

run_step "Basic info" "$T_SYSINFO" bash -c '
  sw_vers || true
  sysctl kern.boottime || true
  uptime || true
' || true

run_step "Hardware/Battery" "$T_HW" bash -c '
  system_profiler SPHardwareDataType || true
  pmset -g batt || true
' || true

run_step "Processes snapshot" "$T_SYSINFO" bash -c '
  top -l 1 -n 0 || true
  ps -axo pid,ppid,pcpu,pmem,state,etimes,comm | head -n 200 || true
' || true

run_step "Memory (vm_stat)" "$T_VMSTAT" vm_stat || true
run_step "Disks (df local only)" "$T_DF" df -hl || true

DISKS="$(diskutil info -all 2>/dev/null | awk '/Device Identifier:/ {id=$3} /Internal:/ && $2=="Yes" {print id}' | sort -u | xargs)"
[ -n "$DISKS" ] || DISKS="disk0"
export DISKS

run_step "I/O (iostat 3s)" "$T_IOSTAT" bash -c '
  iostat -d $DISKS -w 1 3 2>/dev/null | sed -n "1,100p" || top -l 2 -s 1 | grep -E "Disks|CPU"
' || true

if command -v powermetrics >/dev/null; then
  run_step "powermetrics (SMC)" "$T_POWERM" bash -c '
    sudo powermetrics --samplers smc -n 1 >"'"$OUT"'/powermetrics.txt" 2>/dev/null || true
  ' || true
  say "File: $OUT/powermetrics.txt"
fi

run_step "DNS/Interfaces/Route" "$T_SYSINFO" bash -c '
  scutil --dns || true
  ifconfig || true
  route -n get default || true
' || true

if command -v networkQuality >/dev/null; then
  run_step "networkQuality test" "$T_NETQ" bash -c '
    networkQuality -v >"'"$OUT"'/networkQuality.txt" 2>/dev/null || true
  ' || true
  say "File: $OUT/networkQuality.txt"
fi

run_step "Unified logs (last 10m errors)" "$T_LOGSHOW" bash -c '
  TMP="'"$OUT"'/errors_10m.log"
  log show --predicate '\''eventType in {"fault","error"}'\'' --last 10m --style syslog 2>/dev/null \
  | grep -E "^[0-9]{4}-[0-9]{2}-[0-9]{2}" > "$TMP" || true
  [[ -s "$TMP" ]] || echo "No errors/faults in last 10 minutes." > "$TMP"
' || true
say "File: $OUT/errors_10m.log"

run_step "Spotlight status" "$T_MDUTIL" bash -c '
  mdutil -sa >"'"$OUT"'/spotlight_status.txt" 2>/dev/null || true
' || true
say "File: $OUT/spotlight_status.txt"

if command -v sysdiagnose >/dev/null; then
  run_step "sysdiagnose (sudo)" "$T_SYSDIAG" bash -c '
    sudo sysdiagnose -f "'"$OUT"'" >/dev/null 2>&1 || true
  ' || true
fi

run_step "Archive results" "$T_TAR" bash -c '
  cd "'"$(dirname "$OUT")"'" && tar -czf "'"$OUT.tgz"'" "'"$(basename "$OUT")"'" >/dev/null 2>&1 || true
' || true

ELAPSED=$(( $(date +%s) - START_TS ))
printf "%s\n" "$OUT.tgz" >&3
say "Done in ${ELAPSED}s. Archive: $OUT.tgz"
