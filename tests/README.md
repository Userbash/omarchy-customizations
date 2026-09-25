Backend contract tests for the local VPN and Bluetooth monitor.

The plugin smoke checks live beside the plugins so they can run without a
Quickshell session:

```bash
bash config/omarchy/plugins/clipboard.local/tests/test_clipboard.sh
bash config/omarchy/plugins/music-desktop/tests/test_music_desktop.sh
node tests/test_notifications_logic.js
bash tests/test_game_guard_e2e.sh
bash tests/test_vpn_speed_smoke.sh
```

The clipboard test covers the local shortcut map, full-history confirmation,
manifest wiring, and shell syntax. The music test checks the animation and
layer contract. The notification test exercises markup filtering, executable
argument validation, Do Not Disturb rules, and history replay.
The game guard E2E check runs the installed command against a fake Hyprland JSON
surface and verifies that a fullscreen Steam game is classified without
touching any real service.
The VPN speed smoke check talks only to the loopback monitor API and runs one
real bounded download/upload test through the active VPN. It requires `curl`,
`jq`, a running `omarchy-vpn-monitor.service`, and an active Throne tunnel.

The music desktop plugin also has focused tests for its parser, cat motion edge
cases, drag hitbox regressions, stale Cava data, restart behavior, and a
Quickshell/Cava smoke run:

```bash
bash config/omarchy/plugins/music-desktop/tests/test_music_desktop.sh
bash config/omarchy/plugins/music-desktop/tests/test_regressions.sh
node config/omarchy/plugins/music-desktop/tests/cat-motion-test.js
node config/omarchy/plugins/music-desktop/tests/cat-motion-edge-test.js
node config/omarchy/plugins/music-desktop/tests/spectrum-parser-test.js
bash config/omarchy/plugins/music-desktop/tests/smoke_music_desktop.sh
```
