#!/usr/bin/env python3
"""Pause the local Qwen stack while a known game owns a fullscreen monitor."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable


GAME_CLASS = re.compile(
    r"^(?:steam_app_[0-9]+|gamescope|steam_game|wine|wine64|lutris|heroic|bottles)$",
    re.IGNORECASE,
)
GAME_TITLE = re.compile(r"\b(bodycam|game|gameplay|unreal|unity|proton|wine)\b", re.IGNORECASE)
GAME_PATH = re.compile(r"(?:/steamapps/common/|/compatdata/[0-9]+/|\.exe(?:\x00|$))", re.IGNORECASE)
DESKTOP_CLASS = re.compile(
    r"^(?:steam|steamwebhelper|discord|brave-browser|firefox|org\.mozilla\.firefox|orca|dolphin|kitty|foot)$",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Decision:
    active: bool
    client: dict | None = None
    reason: str = ""


def _number(value: object) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def monitor_rectangles(monitors: Iterable[dict]) -> list[tuple[float, float, float, float]]:
    rectangles = []
    for monitor in monitors:
        width = _number(monitor.get("width"))
        height = _number(monitor.get("height"))
        scale = _number(monitor.get("scale")) or 1.0
        if width > 0 and height > 0:
            rectangles.append((_number(monitor.get("x")), _number(monitor.get("y")), width / scale, height / scale))
    return rectangles


def fills_monitor(client: dict, rectangles: Iterable[tuple[float, float, float, float]]) -> bool:
    at = client.get("at") or []
    size = client.get("size") or []
    if len(at) != 2 or len(size) != 2:
        return False
    x, y, width, height = map(_number, (*at, *size))
    if width <= 0 or height <= 0:
        return False
    for mx, my, mw, mh in rectangles:
        # Allow reserved bars and fractional rounding, but reject ordinary maximized windows.
        if abs(x - mx) <= 4 and abs(y - my) <= 30 and width >= mw * 0.96 and height >= mh * 0.94:
            return True
    return False


def is_game_client(client: dict, cmdline: str = "") -> bool:
    window_class = str(client.get("class", ""))
    title = str(client.get("title", ""))
    text = " ".join((window_class, title, cmdline))
    if DESKTOP_CLASS.fullmatch(window_class):
        return False
    if GAME_CLASS.fullmatch(window_class) or GAME_TITLE.search(text) or GAME_PATH.search(cmdline):
        return True
    return False


def choose_game(clients: list[dict], monitors: list[dict], cmdline_for_pid: Callable[[int], str]) -> Decision:
    rectangles = monitor_rectangles(monitors)
    for client in clients:
        # Hyprland uses 1 for legacy fullscreen and 2 for fullscreen-with-client
        # state. Both mean the client owns the monitor for this purpose.
        if int(client.get("fullscreen", 0) or 0) < 1:
            continue
        pid = int(client.get("pid", 0) or 0)
        cmdline = cmdline_for_pid(pid) if pid else ""
        if fills_monitor(client, rectangles) and is_game_client(client, cmdline):
            return Decision(True, client, "known game with fullscreen monitor geometry")
    return Decision(False, reason="no known fullscreen game")


def hypr_json(kind: str) -> list[dict]:
    output = subprocess.check_output(["hyprctl", kind, "-j"], text=True, timeout=5)
    value = json.loads(output)
    return value if isinstance(value, list) else []


def proc_cmdline(pid: int) -> str:
    try:
        return Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
    except (FileNotFoundError, PermissionError, OSError):
        return ""


class ServiceController:
    services = (
        "qwen-worker-pool.service",
        "llama-api-router.service",
        "llama-health-watchdog.service",
        "llama-qwen.service",
    )

    def __init__(self, runner: Callable[..., subprocess.CompletedProcess] | None = None, dry_run: bool = False):
        self.runner = runner or subprocess.run
        self.dry_run = dry_run

    def _call(self, action: str, unit: str) -> None:
        if self.dry_run:
            return
        self.runner(["systemctl", "--user", action, unit], check=False, timeout=45)

    def pause(self) -> None:
        for unit in self.services:
            self._call("stop", unit)

    def resume(self) -> None:
        for unit in reversed(self.services):
            self._call("start", unit)


def run_guard(interval: float, enter_samples: int, exit_samples: int, dry_run: bool, once: bool) -> int:
    controller = ServiceController(dry_run=dry_run)
    paused = False
    positive = negative = 0
    last_state: bool | None = None
    while True:
        try:
            decision = choose_game(hypr_json("clients"), hypr_json("monitors"), proc_cmdline)
        except (OSError, subprocess.SubprocessError, json.JSONDecodeError, ValueError):
            decision = Decision(False, reason="Hyprland state unavailable")
        if once or decision.active != last_state:
            payload = {"game": decision.active, "reason": decision.reason}
            if decision.client:
                payload["class"] = decision.client.get("class", "")
                payload["title"] = decision.client.get("title", "")
                payload["pid"] = decision.client.get("pid", 0)
            print(json.dumps(payload, ensure_ascii=False), flush=True)
            last_state = decision.active
        if decision.active:
            positive += 1
            negative = 0
            if not paused and positive >= enter_samples:
                controller.pause()
                paused = True
        else:
            negative += 1
            positive = 0
            if paused and negative >= exit_samples:
                controller.resume()
                paused = False
        if once:
            return 0
        time.sleep(interval)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--enter-samples", type=int, default=2)
    parser.add_argument("--exit-samples", type=int, default=3)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    if args.interval <= 0 or args.enter_samples < 1 or args.exit_samples < 1:
        parser.error("interval and sample counts must be positive")
    return run_guard(args.interval, args.enter_samples, args.exit_samples, args.dry_run, args.once)


if __name__ == "__main__":
    raise SystemExit(main())
