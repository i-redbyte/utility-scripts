#!/usr/bin/env bash
# killport — убить процесс(ы), слушающие порт. Совместим с bash 3.2 (macOS).
set -euo pipefail

usage(){ echo "usage: killport <port> [--dry-run]"; exit 1; }

PORT="${1:-}"; [[ -n "${PORT}" ]] || usage
[[ "$PORT" =~ ^[0-9]+$ && $PORT -ge 1 && $PORT -le 65535 ]] || usage
DRY="${2:-}"

get_pids() {
  ( lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null; \
    lsof -nP -iUDP:"$PORT" -t 2>/dev/null ) | sort -u
}

# Собираем PID'ы без mapfile
PIDS=()
while IFS= read -r pid; do
  [[ -n "$pid" ]] && PIDS+=("$pid")
done < <(get_pids)

if ((${#PIDS[@]}==0)); then
  echo "Ничего не слушает порт $PORT"
  exit 0
fi

echo "Найдены процессы на порту $PORT:"
for pid in "${PIDS[@]}"; do
  name=$(ps -p "$pid" -o comm= 2>/dev/null | awk '{print $1}')
  echo "  PID $pid  ${name:-unknown}"
done

[[ "$DRY" == "--dry-run" ]] && exit 0

for pid in "${PIDS[@]}"; do
  name=$(ps -p "$pid" -o comm= 2>/dev/null | awk '{print $1}')
  printf "Завершаю PID %s (%s)… " "$pid" "${name:-unknown}"
  kill -TERM "$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5; do sleep 0.2; kill -0 "$pid" 2>/dev/null || break; done
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null || { echo "не удалось (нужны права)"; continue; }
    echo "убит SIGKILL."
  else
    echo "остановлен."
  fi
done
