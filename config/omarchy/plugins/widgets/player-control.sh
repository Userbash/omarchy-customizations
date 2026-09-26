#!/bin/sh
# Call playerctl with argv and keep metadata, transport, and volume on one MPRIS player.
set -u

action=${1:-}
value=${2:-}
case "$action" in
  play|pause|stop|volume-get) requested_player=${2:-} ;;
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
      volume=$(read_player_volume "$target") || volume=""
      if [ -n "$volume" ]; then
        printf '%s§%s\n' "$target" "$volume"
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
