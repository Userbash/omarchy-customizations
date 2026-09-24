Backend contract tests for the local VPN and Bluetooth monitor.

The plugin smoke checks live beside the plugins so they can run without a
Quickshell session:

```bash
bash config/omarchy/plugins/clipboard.local/tests/test_clipboard.sh
bash config/omarchy/plugins/music-desktop/tests/test_music_desktop.sh
node tests/test_notifications_logic.js
bash tests/test_game_guard_e2e.sh
```

The clipboard test covers the local shortcut map, full-history confirmation,
manifest wiring, and shell syntax. The music test checks the animation and
layer contract. The notification test exercises markup filtering, executable
argument validation, Do Not Disturb rules, and history replay.
The game guard E2E check runs the installed command against a fake Hyprland JSON
surface and verifies that a fullscreen Steam game is classified without
touching any real service.
