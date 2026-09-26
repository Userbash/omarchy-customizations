#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v quickshell >/dev/null || { printf 'SKIP — quickshell is not installed\n'; exit 0; }
command -v jq >/dev/null || { printf 'SKIP — jq is not installed\n'; exit 0; }

tmp=$(mktemp -d)
qs_pid=""
audio_pid=""
cleanup() {
  local result=$?
  trap - ERR
  if [[ $result -ne 0 && -f "$tmp/quickshell.log" ]]; then
    tail -n 80 "$tmp/quickshell.log" >&2
  fi
  if [[ -n $qs_pid ]]; then
    kill "$qs_pid" 2>/dev/null || true
    wait "$qs_pid" 2>/dev/null || true
  fi
  if [[ -n $audio_pid ]]; then
    kill "$audio_pid" 2>/dev/null || true
    wait "$audio_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
  return "$result"
}
trap cleanup EXIT
trap 'printf "FAILED AT LINE %s\n" "$LINENO" >&2' ERR

mkdir -p "$tmp/config/widgets" "$tmp/home/.config/omarchy/plugins/widgets" \
  "$tmp/home/.local/share/omarchy/weather" "$tmp/bin" "$tmp/state"
cp "$root/tests/fixtures/widgets/shell.qml" "$tmp/config/shell.qml"
cp -a "$root/config/omarchy/plugins/widgets/." "$tmp/config/widgets/"
cp -a "$root/config/omarchy/plugins/widgets/." "$tmp/home/.config/omarchy/plugins/widgets/"
printf '0.65\n' > "$tmp/volume"
printf 'Playing\n' > "$tmp/status"
printf '120\n' > "$tmp/position"
sleep 30 &
audio_pid=$!
printf '42|%s|65|no\n99|1|100|no\n' "$audio_pid" > "$tmp/streams"

cat > "$tmp/bin/playerctl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$PLAYER_CONTROL_LOG"
if [ "${1:-}" = "-l" ]; then
  printf 'fake.player\n'
  exit 0
fi
player=${1#--player=}
[ "${1:-}" = "--player=$player" ] || exit 2
[ "$player" = "fake.player" ] || exit 1
shift
case "${1:-}" in
  status)
    cat "$PLAYERCTL_STATUS_FILE"
    ;;
  metadata)
    status=$(cat "$PLAYERCTL_STATUS_FILE")
    position=$(cat "$PLAYERCTL_POSITION_FILE")
    position_usec=$(awk -v value="$position" 'BEGIN { printf "%.0f", value * 1000000 }')
    printf '%s§Test Artist§Тестовая композиция§Демо-альбом§%s§2400000000\n' "$status" "$position_usec"
    ;;
  volume)
    if [ "$#" -eq 1 ]; then
      cat "$PLAYERCTL_VOLUME_FILE"
    else
      printf '%s\n' "$2" > "$PLAYERCTL_VOLUME_FILE"
    fi
    ;;
  position)
    printf '%s\n' "$2" > "$PLAYERCTL_POSITION_FILE"
    ;;
  play)
    printf 'Playing\n' > "$PLAYERCTL_STATUS_FILE"
    ;;
  pause)
    printf 'Paused\n' > "$PLAYERCTL_STATUS_FILE"
    ;;
  stop)
    printf 'Stopped\n' > "$PLAYERCTL_STATUS_FILE"
    ;;
  *) exit 2 ;;
esac
SH
chmod +x "$tmp/bin/playerctl"

cat > "$tmp/bin/busctl" <<'SH'
#!/bin/sh
printf 'PID=%s\n' "$PLAYER_MPRIS_PID"
SH
cat > "$tmp/bin/pactl" <<'SH'
#!/bin/sh
case "${1:-}" in
  list)
    [ "${2:-}" = "sink-inputs" ] || exit 2
    while IFS='|' read -r id pid volume muted; do
      [ -n "$id" ] || continue
      cat <<EOF
Sink Input #$id
    Mute: $muted
    Volume: front-left: 65536 / ${volume}% / 0.00 dB, front-right: 65536 / ${volume}% / 0.00 dB
    Properties:
        application.process.id = "$pid"
EOF
    done < "$PACTL_STATE_FILE"
    ;;
  set-sink-input-volume)
    awk -F'|' -v id="${2:-}" -v volume="${3%%%}" 'BEGIN { OFS = "|" } $1 == id { $3 = volume } { print }' \
      "$PACTL_STATE_FILE" > "$PACTL_STATE_FILE.next"
    mv "$PACTL_STATE_FILE.next" "$PACTL_STATE_FILE"
    ;;
  set-sink-input-mute)
    muted="${3:-}"
    [ "$muted" = "1" ] && muted=yes
    [ "$muted" = "0" ] && muted=no
    awk -F'|' -v id="${2:-}" -v muted="$muted" 'BEGIN { OFS = "|" } $1 == id { $4 = muted } { print }' \
      "$PACTL_STATE_FILE" > "$PACTL_STATE_FILE.next"
    mv "$PACTL_STATE_FILE.next" "$PACTL_STATE_FILE"
    ;;
  *) exit 2 ;;
esac
SH
chmod +x "$tmp/bin/busctl" "$tmp/bin/pactl"

cat > "$tmp/home/.local/share/omarchy/weather/weather-backend" <<'SH'
#!/bin/sh
printf '14.4 12.5 48 0 0.8 197 3 1 2\n'
SH
chmod +x "$tmp/home/.local/share/omarchy/weather/weather-backend"

export HOME="$tmp/home"
export XDG_STATE_HOME="$tmp/state"
export PATH="$tmp/bin:$PATH"
export PLAYER_CONTROL_LOG="$tmp/playerctl.log"
export PLAYERCTL_VOLUME_FILE="$tmp/volume"
export PLAYERCTL_STATUS_FILE="$tmp/status"
export PLAYERCTL_POSITION_FILE="$tmp/position"
export PLAYER_MPRIS_PID="$$"
export PACTL_STATE_FILE="$tmp/streams"

quickshell --path "$tmp/config/shell.qml" > "$tmp/quickshell.log" 2>&1 &
qs_pid=$!

call() { timeout 4s quickshell ipc --path "$tmp/config/shell.qml" --newest call widgets.test "$@"; }
state() { call state; }
assert() {
  local filter=$1
  local current
  current=$(state)
  jq -e "$filter" <<< "$current" >/dev/null
}
wait_for() {
  local filter=$1
  local attempts=${2:-40}
  local current
  for ((attempt = 0; attempt < attempts; attempt += 1)); do
    if current=$(state 2>/dev/null) && jq -e "$filter" <<< "$current" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  printf 'Timed out waiting for widget state: %s\n' "$filter" >&2
  state >&2 || true
  return 1
}
step() { printf 'PASS — %s\n' "$*"; }
wait_file() {
  local path=$1
  local expected=$2
  for ((attempt = 0; attempt < 40; attempt += 1)); do
    [[ -f $path && $(< "$path") == "$expected" ]] && return 0
    sleep 0.1
  done
  printf 'Timed out waiting for %s to contain %s\n' "$path" "$expected" >&2
  return 1
}

wait_for '.layoutLoaded == true and .playerTarget == "fake.player" and .volumeAvailable == true and .weatherTemp == "+14°C" and (.weatherMeta | contains("Влажность 48%")) and (.weatherWind | startswith("Ветер 0.8 м/с"))'
call resetLayout
assert '.layout.version == 3 and .layout.locked == false and [.layout.sections[].id] == ["weather", "system", "media"]'
step weather backend record and QML parsing

call moveSectionTo media weather false
assert '[.layout.sections[].id] == ["media", "weather", "system"] and .layout.sections[0].tiles == ["player"]'
call moveSectionTo media system true
assert '[.layout.sections[].id] == ["weather", "system", "media"] and .layout.sections[2].tiles == ["player"]'
step section-drag drop order and media player confinement

call addSection 'Рабочая зона'
call renameSection section-1 'Кабинет'
call moveTile cpu section-1 '' true
assert '.layout.sections[] | select(.id == "section-1") | .tiles == ["cpu"]'
call moveTile cpu system gpu false
call moveTile network system cpu false
assert '[.layout.sections[] | select(.id == "system") | .tiles[]] == ["network", "cpu", "gpu", "temperature"]'
call moveTile network system temperature false
assert '[.layout.sections[] | select(.id == "system") | .tiles[]] == ["cpu", "gpu", "network", "temperature"]'
call moveTile player system cpu false
call moveTile player weather '' true
call removeTile player
call removeSection media
assert '.layout.sections[] | select(.id == "media") | .tiles == ["player"]'
available=$(call available)
jq -e 'index("player") == null' <<< "$available" >/dev/null
call removeSection section-1
assert '[.layout.sections[].id] == ["weather", "system", "media"]'
step tile drag reorder, cross-section move, and protected media section

call setLocked true
call moveSectionTo media weather false
call moveTile network weather '' true
assert '.layout.locked == true and [.layout.sections[].id] == ["weather", "system", "media"] and ([.layout.sections[] | select(.id == "system") | .tiles[]] | index("network")) != null'
call resizeTile cpu 1 1
assert '.layout.tileSizes.cpu == {"columns": 2, "rows": 2}'
call resetTileSize cpu
assert '.layout.tileSizes.cpu == {"columns": 1, "rows": 1}'
call setLocked false
call resizeTile cpu 1 1
assert '.layout.tileSizes.cpu == {"columns": 2, "rows": 2}'
call resetTileSize cpu
assert '.layout.tileSizes.cpu == {"columns": 1, "rows": 1}'
call resizeTile gpu 1 0
call resetTileSize gpu
assert '.layout.tileSizes.gpu == {"columns": 1, "rows": 1}'
call removeSection system
assert '[.layout.sections[].id] == ["weather", "media"]'
call addSection 'Система'
call moveSection section-1 -1
assert '[.layout.sections[].id] == ["weather", "section-1", "media"]'
call resetLayout
step movement lock, resize controls, double-click reset handler, and section actions

call theme dark
call wallpaper light light-evening
call wallpaper dark dark-forest
call wallpaperOpacity light 0.45
call wallpaperOpacity dark 0.88
call appearance panelOpacity 0.68
call appearance tileOpacity 0.84
call icons color
call edit
call tab appearance
assert '.editing == true and .editorTab == "appearance" and .layout.theme == "dark" and .layout.appearance.wallpapers.light == "light-evening" and .layout.appearance.wallpapers.dark == "dark-forest" and .layout.appearance.wallpaperOpacity.light == 0.45 and .layout.appearance.wallpaperOpacity.dark == 0.88 and .layout.appearance.panelOpacity == 0.68 and .layout.appearance.tileOpacity == 0.84 and .layout.appearance.weatherIconSet == "color"'
call finish
call resetLayout
step settings theme, wallpaper, opacity, weather icons, and saved layout

call volume 0.32
wait_for '.playerVolume == 0.32 and .playerMuted == false and .volumeWritePending == false'
[[ $(awk -F'|' '$1 == 42 { print $3 }' "$tmp/streams") == '32' ]]
[[ $(< "$tmp/volume") == '0.65' ]]
call volumeUp
wait_for '.playerVolume == 0.37 and .volumeWritePending == false'
[[ $(awk -F'|' '$1 == 42 { print $3 }' "$tmp/streams") == '37' ]]
call volumeDown
wait_for '.playerVolume == 0.32 and .volumeWritePending == false'
[[ $(awk -F'|' '$1 == 42 { print $3 }' "$tmp/streams") == '32' ]]
call previewVolume 0.77
wait_for '.playerVolume == 0.77 and .volumeWritePending == false'
[[ $(awk -F'|' '$1 == 42 { print $3 }' "$tmp/streams") == '77' ]]
sleep 2.2
call mute
wait_for '.playerVolume == 0.77 and .playerMuted == true and .volumeControlEnabled == false and .volumeSliderEnabled == false and .muteButtonEnabled == true and .volumeWritePending == false'
[[ $(awk -F'|' '$1 == 42 { print $4 }' "$tmp/streams") == 'yes' ]]
call previewVolume 0.22
call volumeUp
wait_for '.playerVolume == 0.77 and .playerMuted == true'
[[ $(awk -F'|' '$1 == 42 { print $3 }' "$tmp/streams") == '77' ]]
call mute
wait_for '.playerVolume == 0.77 and .playerMuted == false and .volumeControlEnabled == true and .volumeSliderEnabled == true and .volumeWritePending == false'
[[ $(awk -F'|' '$1 == 42 { print $4 }' "$tmp/streams") == 'no' ]]
[[ $(awk -F'|' '$1 == 42 { print $3 }' "$tmp/streams") == '77' ]]
call volume 0.24
call volume 0.58
wait_for '.playerVolume == 0.58 and .volumeWritePending == false'
[[ $(awk -F'|' '$1 == 42 { print $3 }' "$tmp/streams") == '58' ]]
sleep 2.2
call refreshVolume
wait_for '.playerVolume == 0.58 and .volumeWritePending == false'
step volume slider, buttons, mute, queued writes, and MPRIS readback

call seekBy -10
wait_for '.positionSeconds == 110'
wait_file "$tmp/position" '110.000'
call seekTo 0.5
call endSeek
wait_file "$tmp/position" '1200.000'
call togglePlayback
wait_for '.playerStatus == "Paused"'
call togglePlayback
wait_for '.playerStatus == "Playing"'
call stopPlayback
wait_for '.playerStatus == "Stopped"'
assert '.playerTitle == "Тестовая композиция" and .playerTarget == "fake.player" and .durationSeconds == 2400'
step player metadata, seek slider, skip, play-pause, and stop actions

for ((attempt = 0; attempt < 30; attempt += 1)); do
  if jq -e '.version == 3 and .sections[-1].id == "media"' "$tmp/state/omarchy/widgets/layout.json" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
jq -e '.version == 3 and .locked == false and [.sections[].id] == ["weather", "system", "media"]' \
  "$tmp/state/omarchy/widgets/layout.json" >/dev/null
step layout persistence and version-2 migration

printf 'widget QML IPC end-to-end checks passed\n'
