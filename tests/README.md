# Test guide

## Repository suite

Run the checks that are safe for repeated local use from the repository root:

```bash
bash scripts/check.sh
```

The runner validates JSON and shell syntax, Python compilation, systemd units,
backend and plugin logic, isolated install/uninstall behavior, clipboard
capture, player arguments, KVM JSON output, the game-guard fixture, and the
widget's QML/IPC end-to-end scenario when Quickshell and `jq` are installed. The
backend suite includes read-only probes against the current machine; it does
not start or stop VPNs. Optional tools such as `qmllint`, `qmltestrunner`,
`wtype`, and `shellcheck` are reported as skipped when unavailable.

## Focused tests

Python backend tests:

```bash
env PYTHONPATH=backend python3 -m unittest discover -s tests -q
```

Notification and weather logic:

```bash
node tests/test_notifications_logic.js
node tests/test_weather_model.js
node tests/test_widget_layout.js
node tests/test_widget_qml_contract.js
bash tests/test_widgets_qml_e2e.sh
```

The widget end-to-end test creates a temporary Quickshell configuration, state
directory, and fake MPRIS player. It covers section and tile moves, the layout
lock, resizing and reset, appearance settings, weather line parsing, playback,
seeking, volume readback, mute, and queued writes without changing the desktop
player.

Install scripts, KVM output, player control, and the game-guard fixture:

```bash
bash tests/test_install_scripts.sh
bash tests/test_kvm_metrics.sh
bash tests/test_player_control.sh
bash tests/test_game_guard_e2e.sh
```

Clipboard plugin:

```bash
bash config/omarchy/plugins/clipboard.local/tests/test_clipboard.sh
```

Music desktop plugin:

```bash
bash config/omarchy/plugins/music-desktop/tests/test_music_desktop.sh
bash config/omarchy/plugins/music-desktop/tests/test_regressions.sh
node config/omarchy/plugins/music-desktop/tests/cat-motion-test.js
node config/omarchy/plugins/music-desktop/tests/cat-motion-edge-test.js
node config/omarchy/plugins/music-desktop/tests/spectrum-parser-test.js
bash config/omarchy/plugins/music-desktop/tests/smoke_music_desktop.sh
```

The Quickshell/Cava smoke test runs each process with a short timeout and checks
that the music component loads without QML errors.

## Live smoke tests

These are deliberately separate from `scripts/check.sh` because they interact
with the running desktop or an active VPN:

- `bash scripts/smoke.sh` sends a desktop notification and queries
  `omarchy-shell` for notification-indicator geometry.
- `bash tests/test_vpn_speed_smoke.sh` starts a speed test through the local
  VPN monitor and transfers data through the active VPN. It requires a running
  `omarchy-vpn-monitor.service`, an active Throne tunnel, `curl`, and `jq`.
