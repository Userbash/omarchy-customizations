#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/hyprctl" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "clients -j") printf '%s\n' '[{"class":"steam_app_2406770","title":"Bodycam","pid":1234,"fullscreen":1,"at":[0,0],"size":[2560,1440]}]' ;;
  "monitors -j") printf '%s\n' '[{"x":0,"y":0,"width":2560,"height":1440,"scale":1}]' ;;
  *) exit 2 ;;
esac
EOF
chmod 0755 "$tmp/hyprctl"
output=$(PATH="$tmp:$PATH" python "$root/scripts/llama-game-guard.py" --dry-run --once)
printf '%s\n' "$output" | jq -e '.game == true and .class == "steam_app_2406770"' >/dev/null
printf 'llama game guard e2e: ok\n'
