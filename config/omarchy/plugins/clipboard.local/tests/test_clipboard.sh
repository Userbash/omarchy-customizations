#!/usr/bin/env bash
set -euo pipefail

plugin_dir="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
node "$plugin_dir/tests/clipboard_shortcuts.test.js"
bash -n "$plugin_dir/capture.sh"
jq -e '.id == "clipboard.local" and .entryPoints.overlay == "Clipboard.qml"' "$plugin_dir/manifest.json" >/dev/null
rg -q 'KeyboardActions.js' "$plugin_dir/Clipboard.qml"
rg -q 'action === "clearAll"' "$plugin_dir/Clipboard.qml"
rg -q 'Ctrl\+Del' "$plugin_dir/KeyboardActions.js"
printf 'clipboard smoke tests: ok\n'
