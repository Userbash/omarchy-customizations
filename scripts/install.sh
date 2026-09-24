#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/check.sh"
stamp=$(date +%Y%m%d-%H%M%S)
backup="$HOME/.config/omarchy/backups/omarchy-customizations-$stamp"
mkdir -p "$backup" "$HOME/.config/omarchy/plugins" "$HOME/.config/hypr"
mkdir -p "$HOME/.config/omarchy/hooks/post-update.d"
mkdir -p "$HOME/.local/share/omarchy/vpn-monitor" "$HOME/.config/systemd/user"
mkdir -p "$HOME/.local/bin"
cp -a "$HOME/.config/omarchy/shell.json" "$backup/shell.json" 2>/dev/null || true
cp -a "$HOME/.config/hypr" "$backup/hypr" 2>/dev/null || true
cp -a "$root/config/hypr/." "$HOME/.config/hypr/"
cp -a "$root/config/omarchy/shell.json" "$HOME/.config/omarchy/shell.json"
for plugin in "$root"/config/omarchy/plugins/*; do cp -a "$plugin" "$HOME/.config/omarchy/plugins/"; done
cp -a "$root/config/omarchy/hooks/post-update.d/." "$HOME/.config/omarchy/hooks/post-update.d/"
cp -a "$root/backend/vpn_monitor/." "$HOME/.local/share/omarchy/vpn-monitor/vpn_monitor/"
cp -a "$root/config/systemd/user/omarchy-vpn-monitor.service" "$HOME/.config/systemd/user/omarchy-vpn-monitor.service"
install -m 0755 "$root/scripts/llama-game-guard.py" "$HOME/.local/bin/llama-game-guard"
cp -a "$root/config/systemd/user/llama-game-guard.service" "$HOME/.config/systemd/user/llama-game-guard.service"
systemctl --user daemon-reload
systemctl --user enable --now omarchy-vpn-monitor.service >/dev/null 2>&1 || true
systemctl --user enable --now llama-game-guard.service >/dev/null 2>&1 || true
printf 'Installed. Backup: %s\n' "$backup"
omarchy restart shell >/dev/null 2>&1 || true
hyprctl reload >/dev/null 2>&1 || true
