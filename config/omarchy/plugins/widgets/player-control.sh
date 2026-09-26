#!/bin/sh
# Call playerctl with argv and keep metadata, transport, and volume on one MPRIS player.
set -u

action=${1:-}
value=${2:-}
case "$action" in
  play|pause|stop|volume-get|volume-mute) requested_player=${2:-} ;;
  *) requested_player=${3:-} ;;
esac

valid_position() {
  [ "$#" -eq 1 ] || return 1
  case "$1" in
    ""|*[!0-9.]*|.*|*..*) return 1 ;;
  esac
  awk -v value="$1" 'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value + 0 < 1000000000) }'
}

valid_volume() {
  [ "$#" -eq 1 ] || return 1
  case "$1" in
    ""|*[!0-9.]*|.*|*..*) return 1 ;;
  esac
  awk -v value="$1" 'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value + 0 >= 0 && value + 0 <= 1) }'
}

valid_player() {
  [ "$#" -eq 1 ] || return 1
  case "$1" in
    ""|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
}

select_player() {
  command -v playerctl >/dev/null 2>&1 || return 1
  players=$(playerctl -l 2>/dev/null) || players=""
  [ -n "$players" ] || return 1
  first_player=""

  while IFS= read -r candidate; do
    valid_player "$candidate" || continue
    if [ -z "$first_player" ]; then first_player=$candidate; fi
    status=$(playerctl "--player=$candidate" status 2>/dev/null) || status=""
    if [ "$status" = "Playing" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done <<EOF
$players
EOF

  [ -n "$first_player" ] || return 1
  printf '%s\n' "$first_player"
}

resolve_player() {
  if [ -n "${1:-}" ]; then
    valid_player "$1" || return 2
    printf '%s\n' "$1"
    return 0
  fi
  select_player
}

playerctl_command() {
  player=$1
  shift
  [ "$#" -gt 0 ] || return 2
  command -v playerctl >/dev/null 2>&1 || return 127
  playerctl "--player=$player" "$@" >/dev/null 2>&1
}

read_player_volume() {
  player=$1
  command -v playerctl >/dev/null 2>&1 || return 1
  raw=$(playerctl "--player=$player" volume 2>/dev/null) || raw=""
  [ -n "$raw" ] || return 1
  awk -v value="$raw" 'BEGIN { if (value ~ /^[0-9]+([.][0-9]+)?$/ && value + 0 >= 0 && value + 0 <= 1) { printf "%.3f\n", value + 0; exit 0 } exit 1 }'
}

player_owner_pid() {
  player=$1
  command -v busctl >/dev/null 2>&1 || return 1
  status=$(busctl --user status "org.mpris.MediaPlayer2.$player" 2>/dev/null) || return 1
  owner_pid=$(printf '%s\n' "$status" | awk -F= '$1 == "PID" { print $2; exit }')
  case "$owner_pid" in
    ""|*[!0-9]*) return 1 ;;
  esac
  [ "$owner_pid" -gt 1 ] 2>/dev/null || return 1
  printf '%s\n' "$owner_pid"
}

process_belongs_to_player() {
  process_pid=$1
  owner_pid=$2
  case "$process_pid:$owner_pid" in
    *[!0-9:]*|:*|*:) return 1 ;;
  esac
  depth=0
  while [ "$depth" -lt 32 ]; do
    [ "$process_pid" = "$owner_pid" ] && return 0
    [ "$process_pid" -gt 1 ] 2>/dev/null || return 1
    [ -r "/proc/$process_pid/status" ] || return 1
    parent_pid=$(awk '$1 == "PPid:" { print $2; exit }' "/proc/$process_pid/status" 2>/dev/null)
    case "$parent_pid" in
      ""|*[!0-9]*) return 1 ;;
    esac
    [ "$parent_pid" != "$process_pid" ] || return 1
    process_pid=$parent_pid
    depth=$((depth + 1))
  done
  return 1
}

matching_sink_inputs() {
  player=$1
  command -v pactl >/dev/null 2>&1 || return 1
  owner_pid=$(player_owner_pid "$player") || return 1
  snapshot=$(pactl list sink-inputs 2>/dev/null) || return 1
  records=$(printf '%s\n' "$snapshot" | awk '
    function emit_record() {
      if (id ~ /^[0-9]+$/ && pid ~ /^[0-9]+$/ && volume ~ /^[0-9]+([.][0-9]+)?$/ && mute ~ /^(yes|no)$/)
        print id "|" pid "|" volume "|" mute
    }
    /^Sink Input #[0-9]+/ {
      emit_record()
      id = $3
      sub(/^#/, "", id)
      pid = ""
      volume = ""
      mute = "no"
      next
    }
    /^[[:space:]]*Mute:/ {
      mute = $0
      sub(/^[[:space:]]*Mute:[[:space:]]*/, "", mute)
      sub(/[[:space:]].*/, "", mute)
      next
    }
    /^[[:space:]]*Volume:/ {
      volume = $0
      sub(/^[[:space:]]*Volume:[[:space:]]*/, "", volume)
      sub(/^[^:]*:[[:space:]]*/, "", volume)
      sub(/^[0-9]+[[:space:]]*\/[[:space:]]*/, "", volume)
      sub(/%.*/, "", volume)
      gsub(/[[:space:]]/, "", volume)
      next
    }
    /application\.process\.id[[:space:]]*=/ {
      pid = $0
      sub(/^.*application\.process\.id[[:space:]]*=[[:space:]]*/, "", pid)
      gsub(/"/, "", pid)
      sub(/[[:space:]].*/, "", pid)
    }
    END { emit_record() }
  ')
  [ -n "$records" ] || return 1

  found=no
  while IFS='|' read -r sink_id process_pid volume mute; do
    case "$sink_id:$volume:$mute" in
      *[!0-9.:|a-z]*|:*|*:) continue ;;
    esac
    case "$mute" in yes|no) ;; *) continue ;; esac
    process_belongs_to_player "$process_pid" "$owner_pid" || continue
    printf '%s|%s|%s\n' "$sink_id" "$volume" "$mute"
    found=yes
  done <<EOF
$records
EOF
  [ "$found" = yes ]
}

read_app_volume() {
  player=$1
  streams=$(matching_sink_inputs "$player") || return 1
  printf '%s\n' "$streams" | awk -F'|' '
    NR == 1 { volume = $2; all_muted = ($3 == "yes") }
    NR > 1 && $3 != "yes" { all_muted = 0 }
    END {
      if (NR == 0) exit 1
      value = volume / 100
      if (value > 1) value = 1
      if (value < 0) value = 0
      printf "%.3f§%d\n", value, all_muted ? 1 : 0
    }
  '
}

set_app_volume() {
  streams=$1
  value=$2
  volume_percent=$(awk -v value="$value" 'BEGIN { printf "%d", value * 100 + 0.5 }')
  result=0
  while IFS='|' read -r sink_id volume mute; do
    case "$sink_id" in ""|*[!0-9]*) continue ;; esac
    pactl set-sink-input-volume "$sink_id" "$volume_percent%" >/dev/null 2>&1 || result=1
  done <<EOF
$streams
EOF
  return "$result"
}

set_app_mute() {
  streams=$1
  mute=$2
  case "$mute" in yes) mute_value=1 ;; no) mute_value=0 ;; *) return 2 ;; esac
  result=0
  while IFS='|' read -r sink_id volume current_mute; do
    case "$sink_id" in ""|*[!0-9]*) continue ;; esac
    pactl set-sink-input-mute "$sink_id" "$mute_value" >/dev/null 2>&1 || result=1
  done <<EOF
$streams
EOF
  return "$result"
}

if ! command -v playerctl >/dev/null 2>&1; then
  target=""
else
  target=$(resolve_player "$requested_player") || target=""
fi

case "$action" in
  metadata)
    [ "$#" -eq 1 ] || exit 2
    if [ -z "$target" ]; then
      printf '§Stopped§Ничего не воспроизводится§Запустите плеер, чтобы увидеть текущий трек§§0§0\n'
      exit 0
    fi
    metadata=$(playerctl "--player=$target" metadata --format '{{status}}§{{artist}}§{{title}}§{{album}}§{{position}}§{{mpris:length}}' 2>/dev/null) || metadata=""
    [ -n "$metadata" ] || metadata='Stopped§Ничего не воспроизводится§Запустите плеер, чтобы увидеть текущий трек§§0§0'
    printf '%s§%s\n' "$target" "$metadata"
    exit 0
    ;;
  play|pause|stop)
    [ "$#" -le 2 ] || exit 2
    if [ -n "$target" ] && playerctl_command "$target" "$action"; then exit 0; fi
    ;;
  volume-get)
    [ "$#" -le 2 ] || exit 2
    if [ -n "$target" ]; then
      volume=$(read_app_volume "$target") || volume=""
      if [ -n "$volume" ]; then
        printf '%s§%s\n' "$target" "$volume"
        exit 0
      fi
      volume=$(read_player_volume "$target") || volume=""
      if [ -n "$volume" ]; then
        muted=$(awk -v value="$volume" 'BEGIN { print value + 0 <= 0.001 ? 1 : 0 }')
        printf '%s§%s§%s\n' "$target" "$volume" "$muted"
        exit 0
      fi
    fi
    printf 'unavailable\n'
    exit 0
    ;;
  volume-set)
    [ "$#" -eq 2 ] || [ "$#" -eq 3 ] || exit 2
    valid_volume "$value" || exit 2
    [ -n "$target" ] || exit 1
    streams=$(matching_sink_inputs "$target") || streams=""
    if [ -n "$streams" ]; then
      set_app_volume "$streams" "$value" || exit 1
      exit 0
    fi
    playerctl "--player=$target" volume "$value" >/dev/null 2>&1 && exit 0
    exit 1
    ;;
  volume-mute)
    [ "$#" -le 2 ] || exit 2
    [ -n "$target" ] || exit 1
    streams=$(matching_sink_inputs "$target") || streams=""
    if [ -n "$streams" ]; then
      set_app_mute "$streams" yes || exit 1
      exit 0
    fi
    playerctl "--player=$target" volume 0 >/dev/null 2>&1 && exit 0
    exit 1
    ;;
  volume-unmute)
    [ "$#" -eq 3 ] || exit 2
    valid_volume "$value" || exit 2
    [ -n "$target" ] || exit 1
    streams=$(matching_sink_inputs "$target") || streams=""
    if [ -n "$streams" ]; then
      set_app_volume "$streams" "$value" || exit 1
      set_app_mute "$streams" no || exit 1
      exit 0
    fi
    playerctl "--player=$target" volume "$value" >/dev/null 2>&1 && exit 0
    exit 1
    ;;
  position)
    [ "$#" -eq 2 ] || [ "$#" -eq 3 ] || exit 2
    valid_position "$value" || exit 2
    if [ -n "$target" ] && playerctl_command "$target" position "$value"; then exit 0; fi
    ;;
  *)
    exit 2
    ;;
esac

# Keep the existing MPD fallback for transport and seeking when no MPRIS command succeeds.
runtime_dir=${XDG_RUNTIME_DIR:-}
socket="$runtime_dir/mpd.sock"
if [ -S "$socket" ] && command -v socat >/dev/null 2>&1; then
  case "$action" in
    play) mpd_command=play ;;
    pause) mpd_command='pause 1' ;;
    stop) mpd_command=stop ;;
    position) mpd_command="seekcur $value" ;;
  esac
  printf '%s\n' "$mpd_command" | timeout 2s socat - "UNIX-CONNECT:$socket" >/dev/null 2>&1 && exit 0
fi

exit 1
