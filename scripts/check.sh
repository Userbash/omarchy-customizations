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
while IFS= read -r f; do bash -n "$f" && pass "$f" || fail "$f"; done < <(find "$root/config/omarchy/hooks" "$root/config/omarchy/plugins" -type f \( -name '*.sh' -o -name '*.hook' -o -name 'metrics-backend' \) -print)
python3 -m py_compile "$root/scripts/llama-game-guard.py" && pass llama-game-guard.py || fail llama-game-guard.py
python3 -m unittest "$root/tests/test_game_guard.py" && pass 'game guard unit tests' || fail 'game guard unit tests'
for unit in "$root"/config/systemd/user/*.service; do systemd-analyze verify "$unit" && pass "$unit" || fail "$unit"; done
PYTHONPATH="$root/backend" python3 -m unittest discover -s "$root/tests" -q && pass 'backend unit tests' || fail 'backend unit tests'
node "$root/tests/test_notifications_logic.js" && pass 'notification logic tests' || fail 'notification logic tests'
bash "$root/tests/test_install_scripts.sh" && pass 'isolated install/uninstall tests' || fail 'isolated install/uninstall tests'
for test in "$root"/config/omarchy/plugins/clipboard.local/tests/test_clipboard.sh "$root"/config/omarchy/plugins/music-desktop/tests/test_music_desktop.sh; do bash "$test" && pass "$test" || fail "$test"; done
bash "$root/tests/test_game_guard_e2e.sh" && pass 'game guard e2e' || fail 'game guard e2e'
bash "$root/config/omarchy/plugins/music-desktop/tests/test_regressions.sh" && pass 'music regression tests' || fail 'music regression tests'
node "$root/config/omarchy/plugins/music-desktop/tests/cat-motion-test.js" && pass 'cat motion tests' || fail 'cat motion tests'
node "$root/config/omarchy/plugins/music-desktop/tests/cat-motion-edge-test.js" && pass 'cat motion edge tests' || fail 'cat motion edge tests'
node "$root/config/omarchy/plugins/music-desktop/tests/spectrum-parser-test.js" && pass 'spectrum parser tests' || fail 'spectrum parser tests'
git -C "$root" diff --check && pass 'git diff check' || fail 'git diff check'
for tool in qmllint qmltestrunner wtype shellcheck; do command -v "$tool" >/dev/null && pass "$tool" || printf 'SKIP — %s is not installed\n' "$tool"; done
exit "$status"
