#!/usr/bin/env bash
set -euo pipefail
plugin_dir="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

command -v cava >/dev/null
command -v quickshell >/dev/null

cava_out=$(mktemp)
cava_err=$(mktemp)
qs_out=$(mktemp)
qs_err=$(mktemp)
trap 'rm -f "$cava_out" "$cava_err" "$qs_out" "$qs_err"' EXIT

set +e
timeout 4s cava -p "$plugin_dir/cava.conf" >"$cava_out" 2>"$cava_err"
cava_status=$?
set -e
[[ "$cava_status" -eq 124 ]]
[[ ! -s "$cava_err" ]]
awk -v expected=144 '
  NR <= 3 {
    line = $0
    gsub(/^[;[:space:]]+|[;[:space:]]+$/, "", line)
    fields = split(line, values, /[;[:space:]]+/)
    if (fields != expected) exit 1
    seen = NR
  }
  END { exit (seen == 3 ? 0 : 1) }
' "$cava_out"

set +e
timeout 5s quickshell --no-duplicate --path "$plugin_dir/MusicDesktop.qml" >"$qs_out" 2>"$qs_err"
qs_status=$?
set -e
[[ "$qs_status" -eq 124 ]]
rg -q 'Configuration Loaded' "$qs_out"
if rg -q 'ERROR|ReferenceError|TypeError|Cannot assign' "$qs_out" "$qs_err"; then
  cat "$qs_out" "$qs_err" >&2
  exit 1
fi
printf 'ok - cava stream smoke\n'
printf 'ok - quickshell load smoke\n'
