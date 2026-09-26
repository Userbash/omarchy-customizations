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
    printf '%s\n' "${PLAYERCTL_VOLUME:-0.65}"
    ;;
esac
SH
chmod +x "$tmp/bin/playerctl"

control="$root/config/omarchy/plugins/widgets/player-control.sh"
run_control() {
  PATH="$tmp/bin:$PATH" PLAYER_CONTROL_LOG="$tmp/calls.log" PLAYERCTL_VOLUME=0.65 sh "$control" "$@"
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

: >"$tmp/calls.log"
volume=$(run_control volume-get brave.instance48554)
[[ "$volume" == 'brave.instance48554§0.650' ]]
[[ $(<"$tmp/calls.log") == '--player=brave.instance48554 volume' ]]

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
