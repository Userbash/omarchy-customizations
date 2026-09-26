#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/playerctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PLAYER_CONTROL_LOG"
if [[ ${1:-} == -l ]]; then
  printf '%s\n' 'brave.instance48554' 'plasma-browser-integration'
  exit 0
fi
player=${1#--player=}
[[ $1 == --player=* ]] || exit 2
shift
case ${1:-} in
  status)
    [[ $player == brave.instance48554 ]] && printf 'Playing\n' || printf 'Paused\n'
    ;;
  metadata)
    printf 'Playing§Test Artist§Test Title§Test Album§180000000§3960000000\n'
    ;;
  volume)
    if [[ $# == 1 ]]; then
      cat "$PLAYERCTL_VOLUME_FILE"
    else
      printf '%s\n' "$2" > "$PLAYERCTL_VOLUME_FILE"
    fi
    ;;
esac
SH
chmod +x "$tmp/bin/playerctl"
cat > "$tmp/bin/busctl" <<'SH'
#!/bin/sh
printf 'PID=%s\n' "$PLAYER_MPRIS_PID"
SH
cat > "$tmp/bin/pactl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$PACTL_LOG"
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
    id=${2:-}
    volume=${3%%%}
    awk -F'|' -v id="$id" -v volume="$volume" 'BEGIN { OFS = "|" } $1 == id { $3 = volume } { print }' \
      "$PACTL_STATE_FILE" > "$PACTL_STATE_FILE.next"
    mv "$PACTL_STATE_FILE.next" "$PACTL_STATE_FILE"
    ;;
  set-sink-input-mute)
    id=${2:-}
    muted=${3:-}
    [ "$muted" = "1" ] && muted=yes
    [ "$muted" = "0" ] && muted=no
    awk -F'|' -v id="$id" -v muted="$muted" 'BEGIN { OFS = "|" } $1 == id { $4 = muted } { print }' \
      "$PACTL_STATE_FILE" > "$PACTL_STATE_FILE.next"
    mv "$PACTL_STATE_FILE.next" "$PACTL_STATE_FILE"
    ;;
  *) exit 2 ;;
esac
SH
chmod +x "$tmp/bin/busctl" "$tmp/bin/pactl"
printf '0.65\n' > "$tmp/volume"
printf '99|1|100|no\n' > "$tmp/streams"
sleep 30 &
unrelated_child=$!
sleep 30 &
matched_child=$!
trap 'kill "$unrelated_child" "$matched_child" 2>/dev/null || true; rm -rf "$tmp"' EXIT

control="$root/config/omarchy/plugins/widgets/player-control.sh"
run_control() {
  PATH="$tmp/bin:$PATH" PLAYER_CONTROL_LOG="$tmp/calls.log" PLAYERCTL_VOLUME_FILE="$tmp/volume" \
    PLAYER_MPRIS_PID="$$" PACTL_STATE_FILE="$tmp/streams" PACTL_LOG="$tmp/pactl.log" sh "$control" "$@"
}
: >"$tmp/calls.log"
run_control metadata
[[ $(tail -n 1 "$tmp/calls.log") == '--player=brave.instance48554 metadata --format {{status}}§{{artist}}§{{title}}§{{album}}§{{position}}§{{mpris:length}}' ]]
[[ $(PATH="$tmp/bin:$PATH" PLAYER_CONTROL_LOG="$tmp/calls.log" PLAYERCTL_VOLUME=0.65 sh "$control" metadata) == 'brave.instance48554§Playing§Test Artist§Test Title§Test Album§180000000§3960000000' ]]

: >"$tmp/calls.log"
run_control play brave.instance48554
run_control pause brave.instance48554
run_control stop brave.instance48554
run_control position 42.500 brave.instance48554
[[ $(<"$tmp/calls.log") == $'--player=brave.instance48554 play\n--player=brave.instance48554 pause\n--player=brave.instance48554 stop\n--player=brave.instance48554 position 42.500' ]]

: >"$tmp/calls.log"
run_control volume-set 0.35 brave.instance48554
[[ $(<"$tmp/calls.log") == '--player=brave.instance48554 volume 0.35' ]]
volume=$(run_control volume-get brave.instance48554)
[[ "$volume" == 'brave.instance48554§0.350§0' ]]
[[ $(<"$tmp/volume") == '0.35' ]]

: >"$tmp/calls.log"
volume=$(run_control volume-get brave.instance48554)
[[ "$volume" == 'brave.instance48554§0.350§0' ]]
[[ $(<"$tmp/calls.log") == '--player=brave.instance48554 volume' ]]

printf '42|%s|65|no\n99|1|100|no\n' "$matched_child" > "$tmp/streams"
: > "$tmp/pactl.log"
volume=$(run_control volume-get brave.instance48554)
[[ "$volume" == 'brave.instance48554§0.650§0' ]]
run_control volume-set 0.35 brave.instance48554
[[ $(awk -F'|' '$1 == 42 { print $3 }' "$tmp/streams") == '35' ]]
[[ $(awk -F'|' '$1 == 99 { print $3 }' "$tmp/streams") == '100' ]]
[[ $(<"$tmp/volume") == '0.35' ]]
[[ $(run_control volume-get brave.instance48554) == 'brave.instance48554§0.350§0' ]]
run_control volume-mute brave.instance48554
[[ $(awk -F'|' '$1 == 42 { print $4 }' "$tmp/streams") == 'yes' ]]
[[ $(awk -F'|' '$1 == 99 { print $4 }' "$tmp/streams") == 'no' ]]
[[ $(run_control volume-get brave.instance48554) == 'brave.instance48554§0.350§1' ]]
run_control volume-unmute 0.35 brave.instance48554
[[ $(awk -F'|' '$1 == 42 { print $4 }' "$tmp/streams") == 'no' ]]
[[ $(run_control volume-get brave.instance48554) == 'brave.instance48554§0.350§0' ]]
printf 'player process-tree PulseAudio volume and mute controls: ok\n'

printf '99|1|100|no\n' > "$tmp/streams"
run_control volume-mute brave.instance48554
[[ $(<"$tmp/volume") == '0' ]]
run_control volume-unmute 0.43 brave.instance48554
[[ $(<"$tmp/volume") == '0.43' ]]

malicious_position="1; touch $tmp/injected"
if run_control position "$malicious_position" brave.instance48554; then
  echo 'player helper accepted a shell expression as a position' >&2
  exit 1
fi
for invalid_volume in "-0.1" "1.01" "1; touch $tmp/injected"; do
  if run_control volume-set "$invalid_volume" brave.instance48554; then
    echo "player helper accepted invalid volume: $invalid_volume" >&2
    exit 1
  fi
done
if run_control volume-set 0.3 'bad;player'; then
  echo 'player helper accepted an unsafe player id' >&2
  exit 1
fi
if run_control arbitrary; then
  echo 'player helper accepted an unsupported command' >&2
  exit 1
fi
[[ ! -e "$tmp/injected" ]]
printf 'player control, stable MPRIS target, and volume argv tests: ok\n'
