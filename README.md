# Omarchy Customizations

A user-owned Omarchy and Hyprland setup for Quickshell. It keeps the desktop configuration in one portable repository and never edits `/usr/share/omarchy`.

![Omarchy desktop demo](docs/media/omarchy-demo.gif)

## What is included

### Hyprland

`config/hypr/` contains the Lua configuration loaded by Omarchy:

- keybindings and application shortcuts;
- input and appearance settings;
- optional monitor configuration through `OMARCHY_MONITOR` and `OMARCHY_SCALE`;
- startup hooks and Omarchy defaults;
- the custom glass layer rule for the desktop cards.

### Omarchy shell and plugins

- `health` — read-only CPU, memory, disk and temperature widget.
- `weather` — weather bar widget and detail popup.
- `clipboard.local` — clipboard history UI and capture helper.
- `notifications.local` — D-Bus notification service with popup history.
- `notifications-indicator` — right-side bell, unread badge and scrollable missed-notification menu.
- `music-desktop` — music controls, visualizer configuration and animated asset.
- `widgets` — weather, system, network and music cards on the desktop layer.
- `config/omarchy/hooks/post-update.d/` — optional Omarchy post-update hooks.

## Requirements

- Omarchy with Hyprland;
- Quickshell;
- `bash`, `jq`, `notify-send`, `hyprctl` and `omarchy-shell`;
- optional: `qmllint`, `qmltestrunner`, `wtype` for deeper QML/E2E checks.

## Install

Run from the repository root:

```bash
./scripts/check.sh
./scripts/install.sh
./scripts/smoke.sh
```

`install.sh` backs up the current `~/.config/hypr` and `~/.config/omarchy/shell.json` before copying files. It installs only user-owned files and then reloads Hyprland and the Omarchy shell.

To select a monitor override before installation:

```bash
export OMARCHY_MONITOR=DP-1
export OMARCHY_SCALE=1.0
./scripts/install.sh
```

Leave `OMARCHY_MONITOR` unset to keep Omarchy's automatic monitor configuration.

## Verification

```bash
./scripts/check.sh
./scripts/smoke.sh
```

The checks validate JSON manifests, shell syntax, notification D-Bus availability and the live notification-indicator geometry. Missing optional QML/E2E tools are reported as `SKIP`, never as false successes.

## Uninstall

```bash
./scripts/uninstall.sh
```

The uninstall script moves installed plugin directories into a timestamped backup. It does not delete notification or clipboard history.

## Privacy and portability

The repository contains no state databases, notification history, screenshots, credentials, tokens or home-directory paths. Personal machine details are supplied through environment variables or Omarchy's own defaults. Review local changes before publishing a fork.

## License

MIT. See [LICENSE](LICENSE).
