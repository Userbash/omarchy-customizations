"""Read-only Bluetooth battery discovery through the system D-Bus.

The production transport uses ``busctl --json=short`` so the monitor remains
usable on installations without the optional dbus-next Python package. The
normalization layer is independent of that transport and is fully testable.
"""
from __future__ import annotations

import json
import re
import subprocess
import time
from dataclasses import dataclass


BLUEZ = "org.bluez"
OBJECT_MANAGER = "org.freedesktop.DBus.ObjectManager"
DEVICE1 = "org.bluez.Device1"
ADAPTER1 = "org.bluez.Adapter1"
BATTERY1 = "org.bluez.Battery1"
UP_DEVICE = "org.freedesktop.UPower.Device"

ICON_TYPES = {
    "input-mouse": ("mouse", "input-mouse"),
    "input-keyboard": ("keyboard", "input-keyboard"),
    "audio-headphones": ("headphones", "audio-headphones"),
    "audio-headset": ("headset", "audio-headset"),
    "audio-card": ("headset", "audio-headset"),
    "phone": ("phone", "phone"),
    "gamepad": ("gamepad", "gamepad"),
}
NAME_RULES = (
    ("headphones", ("buds", "airpods", "headphones", "earphones", "sony wh", "sony wf", "galaxy buds", "redmi buds", "qcy", "jbl tune", "beats", "bose", "soundcore")),
    ("mouse", ("mouse", "mx master", "mx anywhere", "logitech m", "basilisk", "g pro", "deathadder")),
    ("keyboard", ("keyboard", "keychron", "nuphy", "akko", "mx keys")),
    ("gamepad", ("controller", "gamepad", "dualsense", "dualshock", "xbox", "8bitdo", "switch pro")),
    ("phone", ("iphone", "samsung", "pixel", "xiaomi", "redmi", "oneplus")),
)


def unwrap(value):
    """Unwrap a busctl JSON value recursively."""
    if isinstance(value, dict) and "data" in value and set(value) <= {"type", "data"}:
        return unwrap(value["data"])
    if isinstance(value, list):
        return [unwrap(item) for item in value]
    if isinstance(value, dict):
        return {key: unwrap(item) for key, item in value.items()}
    return value


def _prop(props, name, default=None):
    value = props.get(name, default)
    return unwrap(value)


def _battery_value(props):
    value = _prop(props, "Percentage")
    if isinstance(value, bool):
        return None
    try:
        value = float(value)
    except (TypeError, ValueError):
        return None
    if not 0 <= value <= 100:
        return None
    return int(value) if value.is_integer() else round(value, 1)


def classify_device(icon="", device_class=0, uuids=None, name=""):
    if icon in ICON_TYPES:
        return ICON_TYPES[icon]
    lowered = str(name or "").casefold()
    for device_type, words in NAME_RULES:
        if any(word in lowered for word in words):
            return device_type, {
                "headphones": "audio-headphones", "mouse": "input-mouse",
                "keyboard": "input-keyboard", "gamepad": "gamepad", "phone": "phone",
            }[device_type]
    major = (int(device_class or 0) >> 8) & 0x1F
    if major == 0x02:
        return "phone", "phone"
    if major == 0x04:
        return "headphones", "audio-headphones"
    return "unknown", "bluetooth"


def _upower_matches(device, upower):
    address = device["address"].casefold()
    variants = {address, address.replace(":", "_")}
    haystack = " ".join(str(upower.get(key, "")) for key in ("NativePath", "Model", "Serial")).casefold()
    return any(variant in haystack for variant in variants)


def normalize_device(path, props, battery_props=None, upower_devices=()):
    address = str(_prop(props, "Address", ""))
    name = str(_prop(props, "Name", "") or "")
    alias = str(_prop(props, "Alias", "") or name)
    device_type, icon = classify_device(_prop(props, "Icon", ""), _prop(props, "Class", 0), _prop(props, "UUIDs", []), alias or name)
    battery = _battery_value(battery_props or {})
    source = "bluez" if battery is not None else "none"
    charging = None
    matching_upower = next((item for item in upower_devices if _upower_matches({"address": address}, item)), None)
    if matching_upower:
        if battery is None:
            battery = _battery_value(matching_upower)
            if battery is not None:
                source = "upower"
        state = matching_upower.get("State")
        charging = state in (1, 5) if isinstance(state, int) else None
    return {
        "id": path,
        "objectPath": path,
        "address": address,
        "name": name or alias or address,
        "alias": alias or name or address,
        "connected": bool(_prop(props, "Connected", False)),
        "paired": bool(_prop(props, "Paired", False)),
        "trusted": bool(_prop(props, "Trusted", False)),
        "type": device_type,
        "icon": icon,
        "batteryPercent": battery,
        "batteryKnown": battery is not None,
        "charging": charging,
        "batterySource": source,
        "rssi": _prop(props, "RSSI"),
    }


class BusctlTransport:
    """Structured system-bus calls; no shell interpolation is used."""
    def __init__(self, executable="busctl"):
        self.executable = executable

    def call(self, service, path, interface, method, signature="", args=()):
        command = [self.executable, "--system", "--json=short", "call", service, path, interface, method]
        if signature:
            command.append(signature)
            command.extend(str(arg) for arg in args)
        try:
            result = subprocess.run(command, text=True, capture_output=True, timeout=4, check=False)
            if result.returncode != 0:
                return None
            return unwrap(json.loads(result.stdout))
        except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
            return None

    def managed_objects(self):
        result = self.call(BLUEZ, "/", OBJECT_MANAGER, "GetManagedObjects")
        if isinstance(result, list) and len(result) == 1 and isinstance(result[0], dict):
            return result[0]
        return result if isinstance(result, dict) else {}

    def properties(self, service, path, interface):
        result = self.call(service, path, "org.freedesktop.DBus.Properties", "GetAll", "s", (interface,))
        return result if isinstance(result, dict) else {}

    def upower_paths(self):
        result = self.call("org.freedesktop.UPower", "/org/freedesktop/UPower", "org.freedesktop.UPower", "EnumerateDevices")
        if not isinstance(result, list):
            return []
        # busctl represents the single `ao` return tuple as a list containing
        # the object-path array on some versions.
        if len(result) == 1 and isinstance(result[0], list):
            return result[0]
        return result


@dataclass
class BluetoothBatteryService:
    transport: object
    poll_interval_seconds: int = 90
    include_disconnected: bool = False

    def snapshot(self):
        try:
            objects = self.transport.managed_objects()
        except Exception:
            return {"adapterPowered": False, "updatedAt": int(time.time()), "devices": []}
        adapters = [interfaces.get(ADAPTER1, {}) for interfaces in objects.values() if ADAPTER1 in interfaces]
        adapter_powered = any(bool(_prop(adapter, "Powered", False)) for adapter in adapters)
        upower = []
        try:
            for path in self.transport.upower_paths():
                props = self.transport.properties("org.freedesktop.UPower", path, UP_DEVICE)
                if props:
                    upower.append(props)
        except Exception:
            upower = []
        devices = []
        for path, interfaces in objects.items():
            props = interfaces.get(DEVICE1)
            if not props:
                continue
            if not self.include_disconnected and not bool(_prop(props, "Connected", False)):
                continue
            devices.append(normalize_device(path, props, interfaces.get(BATTERY1, {}), upower))
        devices.sort(key=lambda item: (not item["connected"], not item["batteryKnown"], item["type"], item["name"].casefold()))
        return {"adapterPowered": adapter_powered, "updatedAt": int(time.time()), "devices": devices}
