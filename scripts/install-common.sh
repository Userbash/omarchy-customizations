#!/usr/bin/env bash

# Shared snapshot helpers for install.sh and uninstall.sh. Paths are relative
# to $HOME and come only from this repository's managed file list.

customizations_home=${CUSTOMIZATIONS_HOME:-$HOME}
customizations_state=${CUSTOMIZATIONS_STATE:-"$customizations_home/.local/share/omarchy-customizations"}

new_backup_dir() {
  local label=$1 base="$customizations_home/.config/omarchy/backups"
  mkdir -p "$base"
  mktemp -d "$base/omarchy-customizations-$label-$(date +%Y%m%d-%H%M%S)-XXXXXX"
}

snapshot_paths() {
  local snapshot=$1 path
  shift
  mkdir -p "$snapshot/data"
  : > "$snapshot/paths"
  : > "$snapshot/missing"
  for path in "$@"; do
    case "$path" in
      ''|/*|../*|*/../*|./*|*/./*|*'//'*)
        echo "Invalid managed path: $path" >&2
        return 1
        ;;
    esac
    printf '%s\n' "$path" >> "$snapshot/paths"
    if [[ -e "$customizations_home/$path" || -L "$customizations_home/$path" ]]; then
      mkdir -p "$snapshot/data/$(dirname "$path")"
      if [[ -d "$customizations_home/$path" ]]; then
        mkdir -p "$snapshot/data/$path"
        cp -a -- "$customizations_home/$path/." "$snapshot/data/$path/"
      else
        cp -a -- "$customizations_home/$path" "$snapshot/data/$(dirname "$path")/"
      fi
    else
      printf '%s\n' "$path" >> "$snapshot/missing"
    fi
  done
}

restore_snapshot() {
  local snapshot=$1 path
  [[ -f "$snapshot/paths" ]] || { echo "Backup manifest is missing: $snapshot/paths" >&2; return 1; }
  [[ -f "$snapshot/missing" ]] || { echo "Backup missing manifest is missing: $snapshot/missing" >&2; return 1; }
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    rm -rf -- "$customizations_home/$path"
    if ! grep -Fqx -- "$path" "$snapshot/missing"; then
      mkdir -p "$customizations_home/$(dirname "$path")"
      cp -a -- "$snapshot/data/$path" "$customizations_home/$path"
    fi
  done < <(tac "$snapshot/paths")
}

managed_paths() {
  local root=$1 plugin hook previous
  printf '%s\n' '.config/hypr'
  printf '%s\n' \
    '.config/omarchy/shell.json' \
    '.local/share/omarchy/vpn-monitor/vpn_monitor' \
    '.config/systemd/user/omarchy-vpn-monitor.service' \
    '.config/systemd/user/llama-game-guard.service' \
    '.local/bin/llama-game-guard'
  for plugin in "$root"/config/omarchy/plugins/*; do printf '.config/omarchy/plugins/%s\n' "$(basename "$plugin")"; done
  for hook in "$root"/config/omarchy/hooks/post-update.d/*; do printf '.config/omarchy/hooks/post-update.d/%s\n' "$(basename "$hook")"; done
  previous="$customizations_state/last-install-backup"
  if [[ -f "$previous" ]]; then
    previous=$(<"$previous")
    if [[ -f "$previous/paths" ]]; then
      case "$previous" in
        "$customizations_home/.config/omarchy/backups/"*) ;;
        *) echo "Invalid backup path: $previous" >&2; return 1 ;;
      esac
    fi
    if [[ -f "$previous/paths" ]]; then
      sed '/^\.config\/hypr$/d' "$previous/paths"
    fi
  fi
}

capture_service_state() {
  local output=$1 unit=$2 enabled=disabled active=inactive
  enabled=$(systemctl --user is-enabled "$unit" 2>/dev/null || true)
  active=$(systemctl --user is-active "$unit" 2>/dev/null || true)
  printf '%s\t%s\t%s\n' "$unit" "${enabled:-disabled}" "${active:-inactive}" >> "$output"
}

restore_service_states() {
  local input=$1 unit enabled active
  [[ -f "$input" ]] || return 0
  while IFS=$'\t' read -r unit enabled active; do
    [[ -n "$unit" ]] || continue
    if [[ "$enabled" == enabled || "$enabled" == enabled-runtime || "$enabled" == linked || "$enabled" == linked-runtime || "$enabled" == alias ]]; then
      systemctl --user enable "$unit"
    else
      systemctl --user disable "$unit" || true
    fi
    if [[ "$active" == active || "$active" == activating || "$active" == reloading ]]; then
      systemctl --user start "$unit"
    else
      systemctl --user stop "$unit" || true
    fi
  done < "$input"
}

assert_command() {
  local command_name=$1
  command -v "$command_name" >/dev/null 2>&1 || { echo "Required command is missing: $command_name" >&2; return 1; }
}
