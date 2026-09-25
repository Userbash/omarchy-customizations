#!/usr/bin/env bash
set -euo pipefail
plugin_dir="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
qml="$plugin_dir/MusicDesktop.qml"
catmotion="$plugin_dir/CatMotion.js"
failures=0
check() {
  local label="$1"; shift
  if "$@"; then printf 'ok - %s\n' "$label"; else printf 'not ok - %s\n' "$label"; failures=$((failures+1)); fi
}
check "shared sprite dimensions are declared" rg -q 'readonly property int spriteWidth: 138' "$qml"
check "shared sprite height is declared" rg -q 'readonly property int spriteHeight: 146' "$qml"
check "cat hitbox uses sprite dimensions" bash -c 'rg -q "width: root.spriteWidth" "$0" && rg -q "height: root.spriteHeight" "$0"' "$qml"
check "cat height no longer fills the stage" bash -c '! rg -q "height: parent\\.height" "$0"' "$qml"
check "movement uses sprite width and height" bash -c 'rg -q "catStage.width - root.spriteWidth" "$0" && rg -q "catStage.height - root.spriteHeight" "$0" && rg -q "this.spriteWidth" "$1" && rg -q "this.spriteHeight" "$1"' "$qml" "$catmotion"
check "drag offset is stored" rg -q 'dragOffsetX' "$qml"
check "drag cancellation is handled" rg -q 'onCanceled:' "$qml"
check "stale spectrum watchdog exists" rg -q 'lastSpectrumAt' "$qml"
check "stale spectrum is cleared" rg -q 'clearSpectrum' "$qml"
check "stderr is captured" rg -q 'stderr:' "$qml"
check "all cava exits schedule restart" bash -c 'rg -q "onExited" "$0" && rg -q "restartTimer\\.restart" "$0"' "$qml"
check "restart backoff is bounded" rg -q 'cavaRestartCount' "$qml"
check "consecutive cava failures have a retry limit" bash -c 'rg -q "cavaMaxRetries" "$0" && rg -q "cavaConsecutiveFailures" "$0"' "$qml"
check "successful samples reset retry state" rg -q 'cavaConsecutiveFailures = 0' "$qml"
check "restart timer preserves exponential backoff" bash -c '! sed -n "/id: restartTimer/,/^[[:space:]]*}/p" "$0" | rg -q "cavaBackoffSeconds = 2"' "$qml"
check "only one screen owns shared cat state" rg -q 'model: root.targetScreen' "$qml"
check "pose is cached per frame" rg -q 'root.catPose = Motion.CatMotion.pose' "$qml"
check "motion backend rejects non-finite stage values" rg -q 'Number\(stageWidth\)' "$catmotion"
if (( failures > 0 )); then printf '%s test(s) failed\n' "$failures" >&2; exit 1; fi
