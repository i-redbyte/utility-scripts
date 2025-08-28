#!/usr/bin/env bash
# vol — управление громкостью (macOS, AppleScript)
# usage: vol [mute|unmute|toggle|up [STEP]|down [STEP]|set <0..100>|status]
set -euo pipefail

cmd="${1:-status}"
arg="${2:-}"

case "$cmd" in
  mute)
    osascript -e 'set volume with output muted'
    ;;

  unmute)
    osascript -e 'set volume without output muted'
    ;;

  toggle)
    osascript -e '
      set m to output muted of (get volume settings)
      if m then set volume without output muted else set volume with output muted
      return "muted=" & (not m)
    '
    ;;

  up)
    step="${arg:-10}"
    osascript -e "
      set s to (get volume settings)
      set v to output volume of s
      set nv to v + $step
      if nv > 100 then set nv to 100
      set volume output volume nv
      return nv
    "
    ;;

  down)
    step="${arg:-10}"
    osascript -e "
      set s to (get volume settings)
      set v to output volume of s
      set nv to v - $step
      if nv < 0 then set nv to 0
      set volume output volume nv
      return nv
    "
    ;;

  set)
    : "${arg:?usage: vol set <0..100>}"
    osascript -e "
      set nv to $arg
      if nv < 0 then set nv to 0
      if nv > 100 then set nv to 100
      set volume output volume nv
      return nv
    "
    ;;

  status|*)
    osascript -e '
      set s to (get volume settings)
      return "output=" & (output volume of s) & " muted=" & (output muted of s) & ¬
             " input=" & (input volume of s) & " alert=" & (alert volume of s)
    '
    ;;
esac
