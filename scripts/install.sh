#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/check.sh"
stamp=$(date +%Y%m%d-%H%M%S)
backup="$HOME/.config/omarchy/backups/omarchy-customizations-$stamp"
mkdir -p "$backup" "$HOME/.config/omarchy/plugins" "$HOME/.config/hypr"
mkdir -p "$HOME/.config/omarchy/hooks/post-update.d"
cp -a "$HOME/.config/omarchy/shell.json" "$backup/shell.json" 2>/dev/null || true
cp -a "$HOME/.config/hypr" "$backup/hypr" 2>/dev/null || true
cp -a "$root/config/hypr/." "$HOME/.config/hypr/"
cp -a "$root/config/omarchy/shell.json" "$HOME/.config/omarchy/shell.json"
for plugin in "$root"/config/omarchy/plugins/*; do cp -a "$plugin" "$HOME/.config/omarchy/plugins/"; done
cp -a "$root/config/omarchy/hooks/post-update.d/." "$HOME/.config/omarchy/hooks/post-update.d/"
printf 'Installed. Backup: %s\n' "$backup"
omarchy restart shell >/dev/null 2>&1 || true
hyprctl reload >/dev/null 2>&1 || true
