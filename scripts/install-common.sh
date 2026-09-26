#!/usr/bin/env bash

# Shared snapshot helpers for install.sh and uninstall.sh. Manifests contain
# only this repository's managed paths, relative to the physical home path.

customizations_home=${CUSTOMIZATIONS_HOME:-${HOME:-}}
customizations_state=${CUSTOMIZATIONS_STATE:-}

initialize_customizations_paths() {
  local requested_home requested_state
  requested_home=${CUSTOMIZATIONS_HOME:-${HOME:-}}
  if [[ -z "$requested_home" || ! -d "$requested_home" ]]; then
    echo "Home directory is missing or unavailable: ${requested_home:-<unset>}" >&2
    return 1
  fi
  customizations_home=$(cd -- "$requested_home" && pwd -P) || return 1

  requested_state=${CUSTOMIZATIONS_STATE:-"$customizations_home/.local/share/omarchy-customizations"}
  customizations_state=$(realpath -m -- "$requested_state") || {
    echo "Unable to resolve customization state directory: $requested_state" >&2
    return 1
  }
  [[ "$customizations_state" == /* ]] || {
    echo "Customization state directory must resolve to an absolute path" >&2
    return 1
  }
}

is_safe_relative_path() {
  local path=$1 component
  local -a components=()
  [[ -n "$path" && "$path" != /* && "$path" != *//* && ! "$path" =~ [[:cntrl:]] ]] || return 1
  IFS='/' read -r -a components <<< "$path"
  ((${#components[@]} > 0)) || return 1
  for component in "${components[@]}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
  done
}

is_managed_path() {
  local path=$1 child
  is_safe_relative_path "$path" || return 1
  case "$path" in
    .config/hypr|\
    .config/omarchy/shell.json|\
    .local/share/omarchy/vpn-monitor/vpn_monitor|\
    .config/systemd/user/omarchy-vpn-monitor.service|\
    .config/systemd/user/llama-game-guard.service|\
    .local/bin/llama-game-guard)
      return 0
      ;;
    .config/omarchy/plugins/*)
      child=${path#.config/omarchy/plugins/}
      [[ -n "$child" && "$child" != */* ]]
      ;;
    .config/omarchy/hooks/post-update.d/*)
      child=${path#.config/omarchy/hooks/post-update.d/}
      [[ -n "$child" && "$child" != */* ]]
      ;;
    *)
      return 1
      ;;
  esac
}

assert_safe_home_directory_path() {
  local relative=$1 current=$customizations_home component
  local -a components=()
  is_safe_relative_path "$relative" || {
    echo "Invalid relative home path: $relative" >&2
    return 1
  }
  IFS='/' read -r -a components <<< "$relative"
  for component in "${components[@]}"; do
    current="${current%/}/$component"
    if [[ -L "$current" ]]; then
      echo "Refusing to traverse symbolic link in home path: $current" >&2
      return 1
    fi
    if [[ -e "$current" && ! -d "$current" ]]; then
      echo "Expected a directory in home path: $current" >&2
      return 1
    fi
  done
}

ensure_safe_home_directory_path() {
  local relative=$1
  assert_safe_home_directory_path "$relative" || return 1
  mkdir -p -- "$customizations_home/$relative"
  assert_safe_home_directory_path "$relative"
}

assert_safe_home_target_path() {
  local relative=$1 current=$customizations_home component i
  local -a components=()
  is_safe_relative_path "$relative" || {
    echo "Invalid relative home path: $relative" >&2
    return 1
  }
  IFS='/' read -r -a components <<< "$relative"
  for ((i = 0; i < ${#components[@]} - 1; i++)); do
    component=${components[i]}
    current="${current%/}/$component"
    if [[ -L "$current" ]]; then
      echo "Refusing to traverse symbolic link in home path: $current" >&2
      return 1
    fi
    if [[ -e "$current" && ! -d "$current" ]]; then
      echo "Expected a directory in home path: $current" >&2
      return 1
    fi
  done
}

assert_safe_absolute_directory_path() {
  local directory=$1 current=/ component
  local -a components=()
  [[ "$directory" == /* && ! "$directory" =~ [[:cntrl:]] ]] || {
    echo "Invalid absolute directory path: $directory" >&2
    return 1
  }
  IFS='/' read -r -a components <<< "${directory#/}"
  for component in "${components[@]}"; do
    [[ -n "$component" ]] || continue
    current="${current%/}/$component"
    if [[ -L "$current" ]]; then
      echo "Refusing to traverse symbolic link in directory path: $current" >&2
      return 1
    fi
    if [[ -e "$current" && ! -d "$current" ]]; then
      echo "Expected a directory in path: $current" >&2
      return 1
    fi
  done
}

ensure_safe_absolute_directory_path() {
  local directory=$1
  assert_safe_absolute_directory_path "$directory" || return 1
  mkdir -p -- "$directory"
  assert_safe_absolute_directory_path "$directory"
}

assert_safe_absolute_file_path() {
  local file=$1 parent
  [[ "$file" == /* && ! "$file" =~ [[:cntrl:]] ]] || {
    echo "Invalid absolute file path: $file" >&2
    return 1
  }
  parent=$(dirname -- "$file")
  assert_safe_absolute_directory_path "$parent" || return 1
  if [[ -L "$file" || ( -e "$file" && ! -f "$file" ) ]]; then
    echo "Refusing to use non-regular state file: $file" >&2
    return 1
  fi
}

validate_backup_directory() {
  local directory=$1 relative canonical name
  case "$directory" in
    "$customizations_home"/.config/omarchy/backups/*) ;;
    *) echo "Invalid backup directory: $directory" >&2; return 1 ;;
  esac
  relative=${directory#"$customizations_home"/}
  is_safe_relative_path "$relative" || {
    echo "Invalid backup directory: $directory" >&2
    return 1
  }
  case "$relative" in
    .config/omarchy/backups/omarchy-customizations-*) ;;
    *) echo "Invalid backup directory: $directory" >&2; return 1 ;;
  esac
  name=${relative##*/}
  [[ "$name" != */* && "$name" != omarchy-customizations- ]] || {
    echo "Invalid backup directory name: $directory" >&2
    return 1
  }
  assert_safe_home_directory_path "$relative" || return 1
  [[ -d "$directory" && ! -L "$directory" ]] || {
    echo "Backup directory is missing or unsafe: $directory" >&2
    return 1
  }
  canonical=$(realpath -e -- "$directory") || return 1
  [[ "$canonical" == "$directory" ]] || {
    echo "Backup directory is not canonical: $directory" >&2
    return 1
  }
}

assert_snapshot_data_entry() {
  local snapshot=$1 relative=$2 current="$snapshot/data" component i
  local -a components=()
  [[ -d "$snapshot/data" && ! -L "$snapshot/data" ]] || {
    echo "Backup data directory is missing or unsafe: $snapshot/data" >&2
    return 1
  }
  IFS='/' read -r -a components <<< "$relative"
  for ((i = 0; i < ${#components[@]}; i++)); do
    component=${components[i]}
    current="$current/$component"
    if ((i < ${#components[@]} - 1)); then
      [[ -d "$current" && ! -L "$current" ]] || {
        echo "Backup data path has an unsafe parent: $current" >&2
        return 1
      }
    elif [[ ! -e "$current" && ! -L "$current" ]]; then
      echo "Backup data is missing for managed path: $relative" >&2
      return 1
    elif [[ ! -L "$current" && ! -d "$current" && ! -f "$current" ]]; then
      echo "Unsupported file type in backup: $current" >&2
      return 1
    fi
  done
}

snapshot_path_is_listed() {
  local needle=$1 candidate
  shift
  for candidate in "$@"; do
    [[ "$candidate" == "$needle" ]] && return 0
  done
  return 1
}

validate_snapshot_manifest() {
  local snapshot=$1 path existing missing_path
  local data_entry
  local -a paths=() missing=() paths_seen=() missing_seen=()
  validate_backup_directory "$snapshot" || return 1
  [[ -f "$snapshot/paths" && ! -L "$snapshot/paths" ]] || {
    echo "Backup manifest is missing or unsafe: $snapshot/paths" >&2
    return 1
  }
  [[ -f "$snapshot/missing" && ! -L "$snapshot/missing" ]] || {
    echo "Backup missing manifest is missing or unsafe: $snapshot/missing" >&2
    return 1
  }
  [[ -d "$snapshot/data" && ! -L "$snapshot/data" ]] || {
    echo "Backup data directory is missing or unsafe: $snapshot/data" >&2
    return 1
  }
  mapfile -t paths < "$snapshot/paths"
  mapfile -t missing < "$snapshot/missing"

  for path in "${paths[@]}"; do
    is_managed_path "$path" || {
      echo "Invalid managed path in backup manifest: $path" >&2
      return 1
    }
    assert_safe_home_target_path "$path" || return 1
    for existing in "${paths_seen[@]}"; do
      if [[ "$path" == "$existing" ]]; then
        echo "Duplicate managed path in backup manifest: $path" >&2
        return 1
      fi
      if [[ "$path" == "$existing/"* || "$existing" == "$path/"* ]]; then
        echo "Overlapping managed paths in backup manifest: $existing and $path" >&2
        return 1
      fi
    done
    paths_seen+=("$path")
  done

  for missing_path in "${missing[@]}"; do
    is_managed_path "$missing_path" || {
      echo "Invalid missing path in backup manifest: $missing_path" >&2
      return 1
    }
    snapshot_path_is_listed "$missing_path" "${paths[@]}" || {
      echo "Missing-path entry is not managed by the backup: $missing_path" >&2
      return 1
    }
    for existing in "${missing_seen[@]}"; do
      if [[ "$missing_path" == "$existing" ]]; then
        echo "Duplicate missing path in backup manifest: $missing_path" >&2
        return 1
      fi
    done
    missing_seen+=("$missing_path")
  done

  for path in "${paths[@]}"; do
    data_entry="$snapshot/data/$path"
    if snapshot_path_is_listed "$path" "${missing[@]}"; then
      if [[ -e "$data_entry" || -L "$data_entry" ]]; then
        echo "Backup marks a present path as missing: $path" >&2
        return 1
      fi
    else
      assert_snapshot_data_entry "$snapshot" "$path" || return 1
    fi
  done
}

new_backup_dir() {
  local label=$1 base="$customizations_home/.config/omarchy/backups" directory
  case "$label" in install|uninstall) ;; *) echo "Invalid backup label: $label" >&2; return 1 ;; esac
  ensure_safe_home_directory_path .config/omarchy/backups || return 1
  chmod 700 -- "$base"
  directory=$(mktemp -d "$base/omarchy-customizations-$label-$(date +%Y%m%d-%H%M%S)-XXXXXX") || return 1
  printf '%s\n' "$directory"
}

snapshot_paths() {
  local snapshot=$1 path target existing
  local -a paths=() seen=()
  shift
  validate_backup_directory "$snapshot" || return 1
  paths=("$@")
  for path in "${paths[@]}"; do
    is_managed_path "$path" || {
      echo "Invalid managed path: $path" >&2
      return 1
    }
    assert_safe_home_target_path "$path" || return 1
    for existing in "${seen[@]}"; do
      if [[ "$path" == "$existing" || "$path" == "$existing/"* || "$existing" == "$path/"* ]]; then
        echo "Duplicate or overlapping managed path: $path" >&2
        return 1
      fi
    done
    seen+=("$path")
  done

  if [[ -L "$snapshot/data" || ( -e "$snapshot/data" && ! -d "$snapshot/data" ) ]]; then
    echo "Backup data path is unsafe: $snapshot/data" >&2
    return 1
  fi
  mkdir -p -- "$snapshot/data"
  : > "$snapshot/paths"
  : > "$snapshot/missing"
  for path in "${paths[@]}"; do
    target="$customizations_home/$path"
    printf '%s\n' "$path" >> "$snapshot/paths"
    if [[ -e "$target" || -L "$target" ]]; then
      if [[ ! -L "$target" && ! -d "$target" && ! -f "$target" ]]; then
        echo "Unsupported file type at managed path: $target" >&2
        return 1
      fi
      mkdir -p -- "$snapshot/data/$(dirname -- "$path")"
      cp -a -- "$target" "$snapshot/data/$(dirname -- "$path")/"
    else
      printf '%s\n' "$path" >> "$snapshot/missing"
    fi
  done
}

restore_snapshot() {
  local snapshot=$1 path target source i
  local -a paths=() missing=()
  validate_snapshot_manifest "$snapshot" || return 1
  mapfile -t paths < "$snapshot/paths"
  mapfile -t missing < "$snapshot/missing"
  for ((i = ${#paths[@]} - 1; i >= 0; i--)); do
    path=${paths[i]}
    assert_safe_home_target_path "$path" || return 1
    target="$customizations_home/$path"
    rm -rf -- "$target"
    if ! snapshot_path_is_listed "$path" "${missing[@]}"; then
      mkdir -p -- "$customizations_home/$(dirname -- "$path")"
      source="$snapshot/data/$path"
      cp -a -- "$source" "$target"
    fi
  done
}

managed_paths() {
  local root=$1 plugin hook previous state_record
  printf '%s\n' '.config/hypr'
  printf '%s\n' \
    '.config/omarchy/shell.json' \
    '.local/share/omarchy/vpn-monitor/vpn_monitor' \
    '.config/systemd/user/omarchy-vpn-monitor.service' \
    '.config/systemd/user/llama-game-guard.service' \
    '.local/bin/llama-game-guard'
  for plugin in "$root"/config/omarchy/plugins/*; do
    [[ -d "$plugin" ]] || continue
    printf '.config/omarchy/plugins/%s\n' "$(basename -- "$plugin")"
  done
  for hook in "$root"/config/omarchy/hooks/post-update.d/*; do
    [[ -e "$hook" || -L "$hook" ]] || continue
    printf '.config/omarchy/hooks/post-update.d/%s\n' "$(basename -- "$hook")"
  done

  state_record="$customizations_state/last-install-backup"
  assert_safe_absolute_directory_path "$customizations_state" || return 1
  assert_safe_absolute_file_path "$state_record" || return 1
  if [[ -f "$state_record" ]]; then
    local -a records=()
    mapfile -t records < "$state_record"
    ((${#records[@]} == 1)) && [[ -n "${records[0]}" ]] || {
      echo "Invalid install backup record: $state_record" >&2
      return 1
    }
    previous=${records[0]}
    validate_backup_directory "$previous" || return 1
    validate_snapshot_manifest "$previous" || return 1
    [[ -f "$previous/services" && ! -L "$previous/services" ]] || {
      echo "Backup service state is missing or unsafe: $previous/services" >&2
      return 1
    }
    sed '/^\.config\/hypr$/d' "$previous/paths"
  fi
}

is_managed_unit() {
  [[ "$1" == omarchy-vpn-monitor.service || "$1" == llama-game-guard.service ]]
}

capture_service_state() {
  local output=$1 unit=$2 enabled=disabled active=inactive parent
  is_managed_unit "$unit" || { echo "Refusing to capture unknown user unit: $unit" >&2; return 1; }
  parent=$(dirname -- "$output")
  validate_backup_directory "$parent" || return 1
  [[ ! -L "$output" && ( ! -e "$output" || -f "$output" ) ]] || {
    echo "Refusing to write unsafe service state file: $output" >&2
    return 1
  }
  enabled=$(systemctl --user is-enabled "$unit" 2>/dev/null || true)
  active=$(systemctl --user is-active "$unit" 2>/dev/null || true)
  printf '%s\t%s\t%s\n' "$unit" "${enabled:-disabled}" "${active:-inactive}" >> "$output"
}

restore_service_states() {
  local input=$1 line unit enabled active extra expected i
  local -a units=() enabled_states=() active_states=()
  [[ -e "$input" || -L "$input" ]] || return 0
  validate_backup_directory "$(dirname -- "$input")" || return 1
  [[ -f "$input" && ! -L "$input" ]] || {
    echo "Service state file is missing or unsafe: $input" >&2
    return 1
  }
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r unit enabled active extra <<< "$line"
    expected=$(printf '%s\t%s\t%s' "$unit" "$enabled" "$active")
    [[ "$line" == "$expected" && -z "$extra" ]] || {
      echo "Invalid service state record" >&2
      return 1
    }
    is_managed_unit "$unit" || { echo "Unknown unit in service state: $unit" >&2; return 1; }
    case "$enabled" in
      enabled|enabled-runtime|linked|linked-runtime|alias|masked|masked-runtime|disabled|static|indirect|generated|transient|bad|not-found) ;;
      *) echo "Invalid enabled state in service record: $enabled" >&2; return 1 ;;
    esac
    case "$active" in
      active|reloading|inactive|failed|activating|deactivating|maintenance|unknown|not-found) ;;
      *) echo "Invalid active state in service record: $active" >&2; return 1 ;;
    esac
    for existing in "${units[@]}"; do
      [[ "$existing" != "$unit" ]] || { echo "Duplicate service state record: $unit" >&2; return 1; }
    done
    units+=("$unit")
    enabled_states+=("$enabled")
    active_states+=("$active")
  done < "$input"

  for ((i = 0; i < ${#units[@]}; i++)); do
    unit=${units[i]}
    enabled=${enabled_states[i]}
    active=${active_states[i]}
    case "$enabled" in
      enabled|enabled-runtime|linked|linked-runtime|alias) systemctl --user enable "$unit" ;;
      *) systemctl --user disable "$unit" || true ;;
    esac
    case "$active" in
      active|activating|reloading) systemctl --user start "$unit" ;;
      *) systemctl --user stop "$unit" || true ;;
    esac
  done
}

assert_command() {
  local command_name=$1
  command -v "$command_name" >/dev/null 2>&1 || { echo "Required command is missing: $command_name" >&2; return 1; }
}
