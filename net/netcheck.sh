#!/usr/bin/env bash
# netcheck — быстрая диагностика сети (macOS + Linux)
set -euo pipefail

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

OS="$(uname -s)"

get_default_iface() {
  if [ "$OS" = "Darwin" ]; then
    route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}'
  else
    ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="dev"){print $(i+1); exit}}'
  fi
}

get_wifi_iface() {
  if [ "$OS" = "Darwin" ]; then
    networksetup -listallhardwareports 2>/dev/null \
      | awk '/Wi-Fi|AirPort/{getline; print $2; exit}'
  else
    # Возьмём первый беспроводной интерфейс (если есть)
    if have iw; then
      iw dev 2>/dev/null | awk '/Interface/{print $2; exit}'
    elif have nmcli; then
      nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}'
    else
      echo ""
    fi
  fi
}

get_ip() {
  local iface="$1"
  if [ -z "${iface:-}" ]; then
    echo "—"; return
  fi
  if [ "$OS" = "Darwin" ]; then
    ipconfig getifaddr "$iface" 2>/dev/null || \
      ifconfig "$iface" 2>/dev/null | awk '/inet /{print $2; exit}' || echo "—"
  else
    ip -4 addr show dev "$iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 || echo "—"
  fi
}

get_ssid() {
  local wiface="$1"
  if [ -z "${wiface:-}" ]; then
    echo "—"; return
  fi
  if [ "$OS" = "Darwin" ] && have networksetup; then
    # У networksetup локализованный вывод — берём всё после двоеточия
    networksetup -getairportnetwork "$wiface" 2>/dev/null | cut -d: -f2- | sed 's/^ //'
  else
    if have iwgetid; then
      iwgetid -r 2>/dev/null || echo "—"
    elif have nmcli; then
      nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}'
    else
      echo "—"
    fi
  fi
}

run_speed_test() {
  bold "Скорость:"
  if [ "$OS" = "Darwin" ] && have networkQuality; then
    networkQuality -v || true
  elif have speedtest; then
    # Ookla CLI
    speedtest --accept-license --accept-gdpr -f json || speedtest || true
  elif have speedtest-cli; then
    speedtest-cli --simple || true
  elif have fast; then
    fast -u || true
  else
    echo "  Нет утилиты для теста скорости."
    echo "  Установите одну из них и повторите:"
    echo "    • macOS: brew install speedtest-cli   (или brew install --cask speedtest)"
    echo "    • Debian/Ubuntu: sudo apt install speedtest-cli"
    echo "    • Fedora: sudo dnf install speedtest-cli"
  fi
}

run_ping() {
  bold "Пинг 1.1.1.1:"
  ping -c 5 1.1.1.1 | tail -n +1 || true
}

main() {
  DEF_IF="$(get_default_iface || true)"
  WIFI_IF="$(get_wifi_iface || true)"
  SSID="$(get_ssid "$WIFI_IF" || true)"
  IP="$(get_ip "${WIFI_IF:-$DEF_IF}")"

  bold "Система: $OS"
  echo "Интерфейс (default): ${DEF_IF:-—}"
  echo "Wi-Fi интерфейс: ${WIFI_IF:-—}"
  echo "SSID: ${SSID:-—}"
  echo "IP: ${IP:-—}"
  echo

  run_speed_test
  echo
  run_ping
}

main "$@"
