#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
stamp=$(date +%Y%m%d-%H%M%S)
backup="$HOME/.config/omarchy/backups/omarchy-customizations-uninstall-$stamp"
mkdir -p "$backup"
cp -a "$HOME/.config/omarchy/shell.json" "$backup/shell.json" 2>/dev/null || true
for plugin in "$root"/config/omarchy/plugins/*; do
  id=$(basename "$plugin")
  [ -d "$HOME/.config/omarchy/plugins/$id" ] && mv "$HOME/.config/omarchy/plugins/$id" "$backup/"
done
printf 'Plugin directories moved to %s\n' "$backup"
