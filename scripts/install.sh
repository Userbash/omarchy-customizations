#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/install-common.sh"
initialize_customizations_paths

if [[ "${OMARCHY_CUSTOMIZATIONS_SKIP_CHECK:-0}" != 1 ]]; then "$root/scripts/check.sh"; fi
for command_name in systemctl omarchy hyprctl install; do assert_command "$command_name"; done
managed_path_output=$(managed_paths "$root")
mapfile -t paths < <(printf '%s\n' "$managed_path_output" | awk 'NF && !seen[$0]++')
backup=$(new_backup_dir install)
snapshot_paths "$backup" "${paths[@]}"
capture_service_state "$backup/services" omarchy-vpn-monitor.service
capture_service_state "$backup/services" llama-game-guard.service

rollback_required=1

restore_on_error() {
  local status=$?
  trap - ERR
  if (( status != 0 && rollback_required )); then
    echo "Installation failed; restoring files from $backup" >&2
    restore_snapshot "$backup" || echo "Automatic file rollback failed; backup is at $backup" >&2
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    restore_service_states "$backup/services" || echo "Automatic service rollback failed; inspect $backup/services" >&2
    omarchy restart shell >/dev/null 2>&1 || true
    hyprctl reload >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap restore_on_error ERR

for path in "${paths[@]}"; do rm -rf -- "$customizations_home/$path"; done
mkdir -p "$customizations_home/.config/omarchy/plugins" \
  "$customizations_home/.config/omarchy/hooks/post-update.d" \
  "$customizations_home/.config/hypr" \
  "$customizations_home/.config/systemd/user" \
  "$customizations_home/.local/share/omarchy/vpn-monitor" \
  "$customizations_home/.local/bin"
cp -a "$root/config/hypr/." "$customizations_home/.config/hypr/"
cp -a "$root/config/omarchy/shell.json" "$customizations_home/.config/omarchy/shell.json"
for plugin in "$root"/config/omarchy/plugins/*; do cp -a "$plugin" "$customizations_home/.config/omarchy/plugins/"; done
cp -a "$root/config/omarchy/hooks/post-update.d/." "$customizations_home/.config/omarchy/hooks/post-update.d/"
mkdir -p "$customizations_home/.local/share/omarchy/vpn-monitor/vpn_monitor"
cp -a "$root/backend/vpn_monitor/." "$customizations_home/.local/share/omarchy/vpn-monitor/vpn_monitor/"
cp -a "$root/config/systemd/user/omarchy-vpn-monitor.service" "$customizations_home/.config/systemd/user/omarchy-vpn-monitor.service"
cp -a "$root/config/systemd/user/llama-game-guard.service" "$customizations_home/.config/systemd/user/llama-game-guard.service"
install -m 0755 "$root/scripts/llama-game-guard.py" "$customizations_home/.local/bin/llama-game-guard"

systemctl --user daemon-reload
systemctl --user enable --now omarchy-vpn-monitor.service
systemctl --user enable --now llama-game-guard.service
omarchy restart shell
hyprctl reload

ensure_safe_absolute_directory_path "$customizations_state"
state_record="$customizations_state/last-install-backup"
assert_safe_absolute_file_path "$state_record"
printf '%s\n' "$backup" > "$state_record"
chmod 600 -- "$state_record"
trap - ERR
rollback_required=0
printf 'Installed successfully. Backup: %s\n' "$backup"
