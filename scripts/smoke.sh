#!/usr/bin/env bash
set -u
command -v notify-send >/dev/null || { printf 'SKIP — notify-send is not installed\n'; exit 0; }
notify-send -u normal 'Omarchy smoke test' 'Notification indicator verification'
sleep 1
omarchy-shell notifications ping >/dev/null && printf 'PASS — D-Bus notifications\n' || exit 1
geometry=$(omarchy-shell shell debugBarGeometry 2>/dev/null || true)
printf '%s' "$geometry" | jq -e '.[] | select(.id=="notifications-indicator" and .visible==true and .width>0)' >/dev/null && printf 'PASS — notification indicator geometry\n' || exit 1
