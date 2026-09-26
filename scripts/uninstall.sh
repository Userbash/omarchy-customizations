#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/install-common.sh"
initialize_customizations_paths
for command_name in systemctl omarchy hyprctl; do assert_command "$command_name"; done

state_backup="$customizations_state/last-install-backup"
assert_safe_absolute_directory_path "$customizations_state"
assert_safe_absolute_file_path "$state_backup"
if [[ ! -f "$state_backup" ]]; then
  echo "No install backup record found at $state_backup; refusing to remove files without a restore point." >&2
  exit 1
fi
mapfile -t backup_records < "$state_backup"
if ((${#backup_records[@]} != 1)) || [[ -z "${backup_records[0]:-}" ]]; then
  echo "Recorded install backup path is invalid: $state_backup" >&2
  exit 1
fi
install_backup=${backup_records[0]}
if ! validate_backup_directory "$install_backup" || ! validate_snapshot_manifest "$install_backup" || \
   [[ ! -f "$install_backup/services" || -L "$install_backup/services" ]]; then
  echo "Recorded install backup is missing or incomplete: $install_backup" >&2
  exit 1
fi

backup=$(new_backup_dir uninstall)
mapfile -t paths < <(sed '/^$/d' "$install_backup/paths")
snapshot_paths "$backup" "${paths[@]}"
capture_service_state "$backup/services" omarchy-vpn-monitor.service
capture_service_state "$backup/services" llama-game-guard.service

rollback_required=1
restore_uninstall_on_error() {
  local status=$?
  trap - ERR
  if (( status != 0 && rollback_required )); then
    echo "Uninstall failed; restoring the installed files from $backup" >&2
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    restore_snapshot "$backup" || echo "Automatic uninstall rollback failed; backup is at $backup" >&2
    restore_service_states "$backup/services" || echo "Automatic service rollback failed; inspect $backup/services" >&2
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    omarchy restart shell >/dev/null 2>&1 || true
    hyprctl reload >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap restore_uninstall_on_error ERR

for unit in llama-game-guard.service omarchy-vpn-monitor.service; do
  if systemctl --user is-enabled "$unit" >/dev/null 2>&1 || systemctl --user is-active "$unit" >/dev/null 2>&1; then
    systemctl --user disable --now "$unit"
  fi
done
systemctl --user daemon-reload
restore_snapshot "$install_backup"
restore_service_states "$install_backup/services"
systemctl --user daemon-reload
omarchy restart shell
hyprctl reload

ensure_safe_absolute_directory_path "$customizations_state"
state_record="$customizations_state/last-uninstall-backup"
assert_safe_absolute_file_path "$state_record"
printf '%s\n' "$backup" > "$state_record"
chmod 600 -- "$state_record"
assert_safe_absolute_file_path "$state_backup"
rm -f -- "$state_backup"
trap - ERR
rollback_required=0
printf 'Uninstalled and restored the pre-install files. Rollback snapshot: %s\n' "$backup"
