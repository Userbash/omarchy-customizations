from __future__ import annotations

import json
import unittest
from unittest.mock import patch

from vpn_monitor.bluetooth import BluetoothBatteryService, BusctlTransport, normalize_device, unwrap
from vpn_monitor.api import ApiApplication
from vpn_monitor.core import VpnMonitor
from vpn_monitor.system import FakeSystem


def bluez_props(**overrides):
    props = {
        "Address": {"type": "s", "data": "AA:BB:CC:DD:EE:FF"},
        "Name": {"type": "s", "data": "Logitech MX Master 3"},
        "Alias": {"type": "s", "data": "Logitech MX Master 3"},
        "Connected": {"type": "b", "data": True},
        "Paired": {"type": "b", "data": True},
        "Trusted": {"type": "b", "data": True},
        "RSSI": {"type": "n", "data": -55},
        "Icon": {"type": "s", "data": "input-mouse"},
    }
    props.update(overrides)
    return props


class BluetoothNormalizationTests(unittest.TestCase):
    def test_bluez_battery_has_priority_and_classifies_icon(self):
        device = normalize_device("/org/bluez/hci0/dev_AA", bluez_props(), {"Percentage": {"type": "y", "data": 82}}, [{"Percentage": 12}])
        self.assertEqual(device["batteryPercent"], 82)
        self.assertEqual(device["batterySource"], "bluez")
        self.assertEqual(device["type"], "mouse")
        self.assertTrue(device["batteryKnown"])

    def test_upower_is_used_when_bluez_battery_is_missing(self):
        props = bluez_props(Address={"type": "s", "data": "80:99:E7:26:D8:49"}, Name={"type": "s", "data": "Sony WH-1000XM5"}, Alias={"type": "s", "data": "Sony WH-1000XM5"}, Icon={"type": "s", "data": "audio-headset"})
        device = normalize_device("/org/bluez/hci0/dev_80", props, {}, [{"NativePath": "bluetooth:80_99_E7_26_D8_49", "Percentage": 40.0, "State": 1}])
        self.assertEqual(device["batteryPercent"], 40)
        self.assertEqual(device["batterySource"], "upower")
        self.assertTrue(device["charging"])
        self.assertEqual(device["type"], "headset")

    def test_unknown_battery_is_null_not_zero(self):
        device = normalize_device("/org/bluez/hci0/dev_AA", bluez_props(), {})
        self.assertIsNone(device["batteryPercent"])
        self.assertFalse(device["batteryKnown"])
        self.assertEqual(device["batterySource"], "none")

    def test_name_fallback_classifies_devices(self):
        props = bluez_props(Name={"type": "s", "data": "DualSense Wireless Controller"}, Alias={"type": "s", "data": "DualSense Wireless Controller"}, Icon={"type": "s", "data": ""})
        device = normalize_device("/org/bluez/hci0/dev_AA", props)
        self.assertEqual((device["type"], device["icon"]), ("gamepad", "gamepad"))

    def test_unwrap_handles_busctl_variant_json(self):
        self.assertEqual(unwrap({"type": "a{sv}", "data": {"Percentage": {"type": "y", "data": 55}}}), {"Percentage": 55})


class FakeTransport:
    def __init__(self, objects, upower=None):
        self.objects, self.upower = objects, upower or []

    def managed_objects(self): return self.objects
    def upower_paths(self): return [item[0] for item in self.upower]
    def properties(self, _service, path, _interface):
        return next((item[1] for item in self.upower if item[0] == path), {})


class BluetoothServiceTests(unittest.TestCase):
    @patch("vpn_monitor.bluetooth.time.monotonic")
    def test_snapshot_cache_avoids_repeated_dbus_reads(self, monotonic):
        monotonic.side_effect = [100.0, 100.5]
        transport = FakeTransport({"/org/bluez/hci0": {"org.bluez.Adapter1": {"Powered": True}}})
        service = BluetoothBatteryService(transport, poll_interval_seconds=3)
        first = service.snapshot()
        second = service.snapshot()
        self.assertEqual(first, second)

    def test_snapshot_filters_disconnected_devices_and_reports_adapter_power(self):
        objects = {
            "/org/bluez/hci0": {"org.bluez.Adapter1": {"Powered": {"type": "b", "data": True}}},
            "/org/bluez/hci0/dev_AA": {"org.bluez.Device1": bluez_props()},
            "/org/bluez/hci0/dev_BB": {"org.bluez.Device1": bluez_props(Connected={"type": "b", "data": False})},
        }
        result = BluetoothBatteryService(FakeTransport(objects)).snapshot()
        self.assertTrue(result["adapterPowered"])
        self.assertEqual(len(result["devices"]), 1)
        self.assertEqual(result["devices"][0]["address"], "AA:BB:CC:DD:EE:FF")

    def test_snapshot_handles_powered_off_adapter(self):
        result = BluetoothBatteryService(FakeTransport({"/org/bluez/hci0": {"org.bluez.Adapter1": {"Powered": False}}})).snapshot()
        self.assertFalse(result["adapterPowered"])
        self.assertEqual(result["devices"], [])

    def test_snapshot_survives_unavailable_bluez(self):
        class BrokenTransport:
            def managed_objects(self): raise RuntimeError("bluez unavailable")
        result = BluetoothBatteryService(BrokenTransport()).snapshot()
        self.assertFalse(result["adapterPowered"])
        self.assertEqual(result["devices"], [])


class BusctlTests(unittest.TestCase):
    @patch("vpn_monitor.bluetooth.subprocess.run")
    def test_transport_uses_json_busctl_without_shell(self, run):
        run.return_value.returncode = 0
        run.return_value.stdout = json.dumps({"type": "ao", "data": [["/a"]]})
        result = BusctlTransport().upower_paths()
        self.assertEqual(result, ["/a"])
        command = run.call_args.args[0]
        self.assertEqual(command[:4], ["busctl", "--system", "--json=short", "call"])
        self.assertNotIn("shell", run.call_args.kwargs)

    @patch("vpn_monitor.bluetooth.subprocess.run")
    def test_transport_flattens_managed_objects_return_tuple(self, run):
        run.return_value.returncode = 0
        run.return_value.stdout = json.dumps({"type": "a{oa{sa{sv}}}", "data": [{"/org/bluez/hci0": {}}]})
        self.assertEqual(BusctlTransport().managed_objects(), {"/org/bluez/hci0": {}})


class BluetoothApiTests(unittest.TestCase):
    def test_status_endpoint_returns_normalized_bluetooth_state(self):
        bluetooth = BluetoothBatteryService(FakeTransport({}))
        bluetooth.snapshot = lambda: {"adapterPowered": True, "updatedAt": 1, "devices": []}
        app = ApiApplication(VpnMonitor(FakeSystem()), None, bluetooth=bluetooth)
        code, headers, body = app.handle("GET", "/api/v1/bluetooth/status")
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(body), {"adapterPowered": True, "updatedAt": 1, "devices": []})
        self.assertEqual(headers["Cache-Control"], "no-store")


if __name__ == "__main__":
    unittest.main()
