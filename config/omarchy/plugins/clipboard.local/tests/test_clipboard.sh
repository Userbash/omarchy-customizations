#!/usr/bin/env bash
set -euo pipefail

plugin_dir="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
node "$plugin_dir/tests/clipboard_shortcuts.test.js"
bash -n "$plugin_dir/capture.sh"
jq -e '.id == "clipboard.local" and .entryPoints.overlay == "Clipboard.qml"' "$plugin_dir/manifest.json" >/dev/null
rg -q 'KeyboardActions.js' "$plugin_dir/Clipboard.qml"
rg -q 'action === "clearAll"' "$plugin_dir/Clipboard.qml"
rg -q 'Ctrl\+Del' "$plugin_dir/KeyboardActions.js"

mkdir -p "$tmp/bin" "$tmp/home"
cat > "$tmp/bin/wl-paste" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == --list-types ]]; then
  printf '%s\n' "${CLIPBOARD_TYPES:-text/plain}"
fi
SH
chmod +x "$tmp/bin/wl-paste"
export HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" PATH="$tmp/bin:$PATH"

text_entry=$(printf 'clipboard text' | bash "$plugin_dir/capture.sh" text)
jq -e '.type == "text" and .text == "clipboard text"' <<< "$text_entry" >/dev/null

image_entry=$(printf 'small image payload' | bash "$plugin_dir/capture.sh" image/png)
image_path=$(jq -r '.path' <<< "$image_entry")
[[ -f "$image_path" && ! -L "$image_path" ]]
[[ $(stat -c '%a' "$(dirname -- "$image_path")") == 700 ]]

unsafe_mime=$(printf 'not an image' | bash "$plugin_dir/capture.sh" 'image/../../outside')
[[ -z "$unsafe_mime" ]]

head -c 262145 /dev/zero | bash "$plugin_dir/capture.sh" text > "$tmp/oversized-text.json"
[[ ! -s "$tmp/oversized-text.json" ]]
head -c 2097153 /dev/zero | bash "$plugin_dir/capture.sh" image/png > "$tmp/oversized-image.json"
[[ ! -s "$tmp/oversized-image.json" ]]

# The image cache has a deterministic file-count ceiling even after many
# distinct clipboard captures.
image_dir="$XDG_STATE_HOME/omarchy/clipboard-images"
for ((i = 0; i < 101; i++)); do
  printf -v name '%064x.png' "$i"
  printf 'old image\n' > "$image_dir/$name"
done
printf 'new payload' | bash "$plugin_dir/capture.sh" image/png > /dev/null
image_count=$(find "$image_dir" -maxdepth 1 -type f | wc -l)
((image_count <= 100))
printf 'clipboard smoke tests: ok\n'
