#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fakebin="$tmp/bin"
home="$tmp/home"
mkdir -p "$fakebin" "$home/.config/omarchy/plugins/music-desktop" \
  "$home/.config/omarchy/hooks/post-update.d" "$home/.config/hypr" \
  "$home/.local/share/omarchy/vpn-monitor/vpn_monitor" "$home/.config/systemd/user" \
  "$home/.local/bin"

cat > "$fakebin/systemctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_LOG"
[[ "${FAIL_SYSTEMCTL_ACTION:-}" != "${2:-}" ]] || exit 1
case "${2:-}" in
  is-enabled) echo disabled; exit 1 ;;
  is-active) echo inactive; exit 3 ;;
esac
exit 0
SH
cat > "$fakebin/omarchy" <<'SH'
#!/usr/bin/env bash
printf 'omarchy %s\n' "$*" >> "$TEST_LOG"
[[ "${FAIL_OMARCHY:-0}" != 1 ]]
SH
cat > "$fakebin/hyprctl" <<'SH'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >> "$TEST_LOG"
[[ "${FAIL_HYPRCTL:-0}" != 1 ]]
SH
chmod +x "$fakebin"/*
export PATH="$fakebin:$PATH" CUSTOMIZATIONS_HOME="$home" CUSTOMIZATIONS_STATE="$home/.local/share/omarchy-customizations" TEST_LOG="$tmp/commands.log" OMARCHY_CUSTOMIZATIONS_SKIP_CHECK=1
ln -s "$(command -v install)" "$fakebin/install"
export HOME="$home"

printf 'original-shell\n' > "$home/.config/omarchy/shell.json"
printf 'original-plugin\n' > "$home/.config/omarchy/plugins/music-desktop/old.qml"
printf 'original-hypr\n' > "$home/.config/hypr/hyprland.lua"
printf 'original-backend\n' > "$home/.local/share/omarchy/vpn-monitor/vpn_monitor/old.py"
printf 'original-hook\n' > "$home/.config/omarchy/hooks/post-update.d/old.hook"
printf 'original-unit\n' > "$home/.config/systemd/user/omarchy-vpn-monitor.service"
printf 'original-guard\n' > "$home/.local/bin/llama-game-guard"

assert_original_state() {
  [[ $(<"$home/.config/omarchy/shell.json") == original-shell ]]
  [[ $(<"$home/.config/omarchy/plugins/music-desktop/old.qml") == original-plugin ]]
  [[ $(<"$home/.config/hypr/hyprland.lua") == original-hypr ]]
  [[ $(<"$home/.local/share/omarchy/vpn-monitor/vpn_monitor/old.py") == original-backend ]]
  [[ $(<"$home/.config/omarchy/hooks/post-update.d/old.hook") == original-hook ]]
  [[ $(<"$home/.config/systemd/user/omarchy-vpn-monitor.service") == original-unit ]]
  [[ $(<"$home/.local/bin/llama-game-guard") == original-guard ]]
}

bash "$root/scripts/install.sh" > "$tmp/install.out"
[[ -f "$home/.config/omarchy/plugins/music-desktop/MusicDesktop.qml" ]]
[[ ! -e "$home/.config/omarchy/plugins/music-desktop/old.qml" ]]
[[ ! -e "$home/.local/share/omarchy/vpn-monitor/vpn_monitor/old.py" ]]
backup=$(<"$home/.local/share/omarchy-customizations/last-install-backup")
[[ -f "$backup/data/.config/omarchy/plugins/music-desktop/old.qml" ]]
[[ -f "$backup/data/.config/systemd/user/omarchy-vpn-monitor.service" ]]

bash "$root/scripts/uninstall.sh" > "$tmp/uninstall.out"
assert_original_state
[[ ! -e "$home/.local/share/omarchy-customizations/last-install-backup" ]]

OMARCHY_CUSTOMIZATIONS_SKIP_CHECK=1 bash "$root/scripts/install.sh" > "$tmp/reinstall.out"
if FAIL_SYSTEMCTL_ACTION=enable OMARCHY_CUSTOMIZATIONS_SKIP_CHECK=1 bash "$root/scripts/install.sh" >"$tmp/failed-install.out" 2>&1; then
  echo 'expected install failure was not reported' >&2
  exit 1
fi
[[ -f "$home/.config/omarchy/plugins/music-desktop/MusicDesktop.qml" ]]
[[ ! -e "$home/.config/omarchy/plugins/music-desktop/old.qml" ]]
[[ -f "$home/.local/share/omarchy-customizations/last-install-backup" ]]
backup_after_failure=$(<"$home/.local/share/omarchy-customizations/last-install-backup")
[[ -d "$backup_after_failure" ]]
OMARCHY_CUSTOMIZATIONS_SKIP_CHECK=1 bash "$root/scripts/uninstall.sh" > "$tmp/final-uninstall.out"
assert_original_state
printf 'install/uninstall isolated tests: ok\n'
