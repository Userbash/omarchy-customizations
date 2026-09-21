#!/usr/bin/env bash
set -u
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
status=0
pass(){ printf 'PASS — %s\n' "$1"; }
fail(){ printf 'FAIL — %s\n' "$1"; status=1; }
command -v jq >/dev/null && pass jq || fail jq
jq empty "$root/config/omarchy/shell.json" && pass shell.json || fail shell.json
while IFS= read -r f; do jq empty "$f" && pass "$f" || fail "$f"; done < <(find "$root/config/omarchy/plugins" -name manifest.json -print)
for f in "$root"/scripts/*.sh; do bash -n "$f" && pass "$f" || fail "$f"; done
for tool in qmllint qmltestrunner wtype; do command -v "$tool" >/dev/null && pass "$tool" || printf 'SKIP — %s отсутствует\n' "$tool"; done
exit "$status"
