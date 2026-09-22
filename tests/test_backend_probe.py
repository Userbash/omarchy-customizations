"""Real-machine smoke tests: read-only probes only, no VPN mutation."""
from __future__ import annotations

import json
import unittest

from vpn_monitor.core import VpnMonitor
from vpn_monitor.system import RealSystem


class RealProbeSmokeTests(unittest.TestCase):
    def setUp(self):
        self.monitor = VpnMonitor(RealSystem())

    def test_clients_are_json_serializable(self):
        clients = self.monitor.clients()
        self.assertGreaterEqual(len(clients), 5)
        json.dumps({"items": clients})
        for client in clients:
            self.assertEqual(set(client["capabilities"]), {"start", "stop", "connect", "disconnect", "toggleInterface", "ping", "speedTest"})

    def test_status_is_json_serializable_without_controlling_any_vpn(self):
        status = self.monitor.overall_status()
        json.dumps(status)
        self.assertIn("items", status)
        for item in status["items"]:
            self.assertIn(item["connection"]["state"], {"DISCONNECTED", "CONNECTED", "DEGRADED", "UNKNOWN"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
