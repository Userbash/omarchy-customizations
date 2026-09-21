#!/usr/bin/env bash
# Static acceptance tests for the user-owned music desktop plugin.
set -euo pipefail

plugin_dir="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
failures=0

check() {
  local label="$1"
  shift
  if "$@"; then
    printf 'ok - %s\n' "$label"
  else
    printf 'not ok - %s\n' "$label"
    failures=$((failures + 1))
  fi
}

check "manifest is valid JSON" jq -e '.id == "music-desktop" and (.kinds | index("service")) and .entryPoints.service == "MusicDesktop.qml"' "$plugin_dir/manifest.json"
check "Cava has a bounded ASCII data protocol" rg -q '^data_format = ascii$' "$plugin_dir/cava.conf"
check "Cava reads the default output monitor, never the microphone" rg -q '^source = auto$' "$plugin_dir/cava.conf"
check "Cava emits exactly 144 bands" rg -q '^bars = 144$' "$plugin_dir/cava.conf"
check "Cava reacts to music at 60 Hz" rg -q '^framerate = 60$' "$plugin_dir/cava.conf"
check "plugin uses a non-interactive Bottom layer" rg -q 'WlrLayershell.layer: WlrLayer.Bottom' "$plugin_dir/MusicDesktop.qml"
check "plugin never takes keyboard focus" rg -q 'WlrLayershell.keyboardFocus: WlrKeyboardFocus.None' "$plugin_dir/MusicDesktop.qml"
check "audio parser clamps malformed values" rg -q 'Math.max\(0, Math.min\(1,' "$plugin_dir/MusicDesktop.qml"
check "cat responds to spectrum peaks as well as average volume" rg -q 'spectrumPeak' "$plugin_dir/MusicDesktop.qml"
check "cat has a 144-frame motion backend" rg -q 'frameCount: 144' "$plugin_dir/CatMotion.js"
check "cat motion follows the rendered display frames" rg -q 'FrameAnimation' "$plugin_dir/MusicDesktop.qml"
check "cat tempo is eased progressively" rg -q 'Motion.CatMotion.smooth\(root.catTempo' "$plugin_dir/MusicDesktop.qml"
check "cat has beat-driven jumps" rg -q 'root.beatPeak > 0.22' "$plugin_dir/MusicDesktop.qml"
check "cat uses bounded beat-driven lean" bash -c 'rg -q "rotation: .*root.catSpin" "$0/MusicDesktop.qml" && ! rg -q "catSpin \+=" "$0/MusicDesktop.qml"' "$plugin_dir"
check "cat has canonical reset defaults" bash -c 'rg -q "catDefaultX" "$0/MusicDesktop.qml" && rg -q "catDefaultY" "$0/MusicDesktop.qml" && rg -q "catDefaultZ" "$0/MusicDesktop.qml"' "$plugin_dir"
check "cat resets after a completed music animation" bash -c 'rg -q "if \(!root.musicActive\)" "$0/MusicDesktop.qml" && rg -q "if \(root.catAnimationActive\) root.resetCatAnimation\(\)" "$0/MusicDesktop.qml"' "$plugin_dir"
check "cat remains in its default pose without music" bash -c 'rg -q "if \(!root.musicActive\)" "$0/MusicDesktop.qml" && rg -q "canonical X/Y/Z pose" "$0/MusicDesktop.qml"' "$plugin_dir"
check "cat resets when its screen surface is recreated" bash -c 'rg -q "Component.onDestruction: root.invalidateCatStage\(catStage\)" "$0/MusicDesktop.qml" && rg -q "function resetCatAnimation\(\)" "$0/MusicDesktop.qml"' "$plugin_dir"
check "an old screen stage cannot stop a new screen" bash -c 'rg -q "if \(root.catStageOwner !== stage\) return" "$0/MusicDesktop.qml" && rg -q "property var catStageOwner" "$0/MusicDesktop.qml"' "$plugin_dir"
check "cat reacts to pointer drag" rg -q 'onPositionChanged: function\(mouse\)' "$plugin_dir/MusicDesktop.qml"
check "cat movement is bounded by the motion backend" rg -q 'Motion.CatMotion.nextPosition' "$plugin_dir/MusicDesktop.qml"
check "cat bobbing is continuously smoothed" rg -q 'root.idleBob = Motion.CatMotion.smooth' "$plugin_dir/MusicDesktop.qml"
check "cat uses the original transparent cat artwork" rg -q 'music-cat-reference.png' "$plugin_dir/MusicDesktop.qml"
check "cat moves freely inside its anchored stage" rg -q 'id: catStage' "$plugin_dir/MusicDesktop.qml"
check "cat has an independent horizontal position" rg -q 'id: catWalker' "$plugin_dir/MusicDesktop.qml"
check "clock has a separate month/day/weekday column" rg -q 'monthText' "$plugin_dir/MusicDesktop.qml"
check "no shell command interpolation is used" bash -c '! rg -q "bash.*-c|sh.*-c|execDetached" "$0/MusicDesktop.qml" "$0/cava.conf"' "$plugin_dir"
check "cat sprite asset is local" test -f "$plugin_dir/assets/music-cat-reference.png"

if (( failures > 0 )); then
  printf '%s test(s) failed\n' "$failures" >&2
  exit 1
fi
