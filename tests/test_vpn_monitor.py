"""Contract tests for the VPN monitor backend.

These tests use fakes only: they never inspect, start, stop, connect or
disconnect a real VPN on this machine.
"""
from __future__ import annotations

import json
import io
import tempfile
import time
import unittest
from pathlib import Path
from subprocess import CompletedProcess, TimeoutExpired
from threading import Event
from unittest.mock import patch

from vpn_monitor.api import ApiApplication
from vpn_monitor.service import make_handler, serve
from vpn_monitor.core import (
    CONNECTION_CONNECTED,
    CONNECTION_DEGRADED,
    CONNECTION_DISCONNECTED,
    CONNECTION_UNKNOWN,
    CLIENT_INSTALLED_STOPPED,
    CLIENT_NOT_INSTALLED,
    CLIENT_RUNNING,
    VpnMonitor,
    TrafficTracker,
)
from vpn_monitor.system import FakeSystem, RealSystem


def interface(name="wg0", *, up=True, ip="10.8.0.2/24", rx=1000, tx=500):
    return {"name": name, "kind": "wireguard", "up": up, "addresses": [ip] if ip else [], "rx": rx, "tx": tx}


class StateMachineTests(unittest.TestCase):
    def test_missing_executable_is_not_installed(self):
        system = FakeSystem()
        status = VpnMonitor(system).status_for("wireguard")
        self.assertEqual(status["client"]["state"], CLIENT_NOT_INSTALLED)
        self.assertEqual(status["connection"]["state"], CONNECTION_UNKNOWN)

    def test_running_process_without_interface_is_disconnected(self):
        system = FakeSystem(executables={"wg-quick": "/usr/bin/wg-quick"}, processes={"wg-quick"})
        status = VpnMonitor(system).status_for("wireguard")
        self.assertTrue(status["client"]["processRunning"])
        self.assertEqual(status["client"]["state"], CLIENT_RUNNING)
        self.assertEqual(status["connection"]["state"], CONNECTION_DISCONNECTED)

    def test_up_addressed_interface_route_and_internet_are_connected(self):
        system = FakeSystem(
            executables={"wg": "/usr/bin/wg", "wg-quick": "/usr/bin/wg-quick"},
            processes={"wg-quick"}, interfaces=[interface()], routes=[{"dev": "wg0", "dst": "0.0.0.0/0"}],
            handshakes={"wg0": True}, internet=True,
        )
        status = VpnMonitor(system).status_for("wireguard")
        self.assertEqual(status["connection"]["state"], CONNECTION_CONNECTED)
        self.assertTrue(status["connection"]["active"])
        self.assertEqual(status["interface"]["state"], "UP")

    def test_kernel_wireguard_without_a_persistent_process_is_connected(self):
        system = FakeSystem(
            executables={"wg": "/usr/bin/wg"},
            interfaces=[interface("wg0")], routes=[{"dev": "wg0", "dst": "0.0.0.0/0"}],
            handshakes={"wg0": True}, internet=True,
        )

        status = VpnMonitor(system).status_for("wireguard")

        self.assertFalse(status["client"]["processRunning"])
        self.assertEqual(status["client"]["state"], CLIENT_RUNNING)
        self.assertEqual(status["connection"]["state"], CONNECTION_CONNECTED)

    def test_kernel_wireguard_is_detected_when_the_cli_was_removed(self):
        system = FakeSystem(
            interfaces=[interface("wg0")], routes=[{"dev": "wg0", "dst": "0.0.0.0/0"}],
            handshakes={"wg0": True}, internet=True,
        )

        status = VpnMonitor(system).status_for("wireguard")

        self.assertTrue(status["client"]["installed"])
        self.assertEqual(status["connection"]["state"], CONNECTION_CONNECTED)

    def test_running_openvpn_process_is_an_installation_signal(self):
        system = FakeSystem(processes={"openvpn"})

        status = VpnMonitor(system).status_for("openvpn")

        self.assertTrue(status["client"]["installed"])
        self.assertEqual(status["client"]["state"], CLIENT_RUNNING)

    def test_running_warp_service_is_an_installation_and_running_signal(self):
        system = FakeSystem(services={"warp-svc.service"})

        status = VpnMonitor(system).status_for("cloudflare-warp")

        self.assertTrue(status["client"]["installed"])
        self.assertTrue(status["client"]["serviceRunning"])
        self.assertEqual(status["client"]["state"], CLIENT_RUNNING)

    def test_running_openvpn_template_service_is_detected_without_a_visible_process(self):
        system = FakeSystem(services={"openvpn-client@office.service"})

        status = VpnMonitor(system).status_for("openvpn")

        self.assertTrue(status["client"]["installed"])
        self.assertTrue(status["client"]["serviceRunning"])
        self.assertEqual(status["client"]["state"], CLIENT_RUNNING)

    def test_warp_does_not_claim_an_unrelated_wireguard_interface(self):
        system = FakeSystem(
            executables={"warp-cli": "/usr/bin/warp-cli"}, processes={"warp-svc"},
            interfaces=[interface("wg0")], routes=[{"dev": "wg0", "dst": "0.0.0.0/0"}], internet=True,
        )

        status = VpnMonitor(system).status_for("cloudflare-warp")

        self.assertEqual(status["connection"]["state"], CONNECTION_DISCONNECTED)

    def test_amneziawg_kernel_tunnel_is_detected_without_a_gui_process(self):
        system = FakeSystem(
            executables={"awg": "/usr/bin/awg"},
            interfaces=[interface("awg0")], routes=[{"dev": "awg0", "dst": "0.0.0.0/0"}], internet=True,
        )

        status = VpnMonitor(system).status_for("amneziawg")

        self.assertEqual(status["client"]["state"], CLIENT_RUNNING)
        self.assertEqual(status["connection"]["state"], CONNECTION_CONNECTED)

    def test_live_interface_without_internet_is_degraded(self):
        system = FakeSystem(
            executables={"openvpn": "/usr/bin/openvpn"}, processes={"openvpn"},
            interfaces=[interface("tun0", ip="10.9.0.2/24")], routes=[{"dev": "tun0", "dst": "0.0.0.0/0"}],
            internet=False,
        )
        status = VpnMonitor(system).status_for("openvpn")
        self.assertEqual(status["connection"]["state"], CONNECTION_DEGRADED)
        self.assertTrue(status["connection"]["active"])

    def test_generic_tun_interface_is_not_assigned_to_two_running_clients(self):
        system = FakeSystem(
            executables={"openvpn": "/usr/bin/openvpn", "amnezia-vpn": "/usr/bin/amnezia-vpn"},
            processes={"openvpn", "amnezia-vpn"},
            interfaces=[interface("tun0", ip="10.9.0.2/24")],
            routes=[{"dev": "tun0", "dst": "0.0.0.0/0"}], internet=True,
        )
        monitor = VpnMonitor(system)

        self.assertEqual(monitor.status_for("openvpn")["connection"]["state"], CONNECTION_DISCONNECTED)
        self.assertEqual(monitor.status_for("amnezia")["connection"]["state"], CONNECTION_DISCONNECTED)
        self.assertNotIn("error", monitor.overall_status())

    def test_throne_is_detected_from_its_binary_process_tunnel_and_route(self):
        system = FakeSystem(
            executables={"Throne": "/usr/bin/Throne"},
            processes={"Throne", "ThroneCore"},
            interfaces=[interface("throne-tun", ip="172.19.0.1/24")],
            routes=[{"dev": "throne-tun", "dst": "default"}], internet=True,
        )
        status = VpnMonitor(system).status_for("throne")
        self.assertEqual(status["client"]["state"], CLIENT_RUNNING)
        self.assertEqual(status["connection"]["state"], CONNECTION_CONNECTED)
        self.assertFalse(status["capabilities"]["connect"])

    def test_active_vpn_exposes_public_exit_country_flag_and_warp_state(self):
        system = FakeSystem(
            executables={"Throne": "/usr/bin/Throne"},
            processes={"Throne", "ThroneCore"},
            interfaces=[interface("throne-tun", ip="172.19.0.1/24")],
            routes=[{"dev": "throne-tun", "dst": "default"}],
            internet=True,
            identity={
                "exitIp": "203.0.113.10",
                "country": "Germany",
                "countryCode": "DE",
                "flag": "\U0001f1e9\U0001f1ea",
                "usesWarp": False,
            },
        )

        status = VpnMonitor(system).status_for("throne")

        self.assertEqual(status["server"], {
            "name": "",
            "country": "Germany",
            "countryCode": "DE",
            "flag": "\U0001f1e9\U0001f1ea",
            "city": "",
            "exitIp": "203.0.113.10",
            "usesWarp": False,
            "viaVpn": True,
        })

    def test_disconnected_client_reports_direct_public_identity_and_country(self):
        system = FakeSystem(
            executables={"Throne": "/usr/bin/Throne"},
            identity={
                "exitIp": "198.51.100.24", "country": "Russia", "countryCode": "RU",
                "flag": "\U0001f1f7\U0001f1fa", "usesWarp": False,
            },
        )

        status = VpnMonitor(system).status_for("throne")

        self.assertEqual(status["connection"]["state"], CONNECTION_DISCONNECTED)
        self.assertEqual(status["server"]["exitIp"], "198.51.100.24")
        self.assertEqual(status["server"]["country"], "Russia")
        self.assertEqual(status["server"]["flag"], "\U0001f1f7\U0001f1fa")
        self.assertFalse(status["server"]["viaVpn"])
        self.assertEqual(system.identity_requests, [(None, None)])

    def test_multiple_active_connections_are_a_conflict(self):
        system = FakeSystem(
            executables={"wg": "/usr/bin/wg", "wg-quick": "/usr/bin/wg-quick", "openvpn": "/usr/bin/openvpn"},
            processes={"wg-quick", "openvpn"},
            interfaces=[interface("wg0"), interface("tun0")],
            routes=[{"dev": "wg0", "dst": "0.0.0.0/0"}, {"dev": "tun0", "dst": "0.0.0.0/0"}],
            handshakes={"wg0": True}, internet=True,
        )
        response = VpnMonitor(system).overall_status()
        self.assertEqual(response["error"]["code"], "MULTIPLE_ACTIVE_VPN_CONNECTIONS")
        self.assertEqual(set(response["error"]["clients"]), {"wireguard", "openvpn"})

    def test_connectivity_result_is_retained_in_the_next_status_poll(self):
        system = FakeSystem(
            executables={"wg": "/usr/bin/wg", "wg-quick": "/usr/bin/wg-quick"},
            processes={"wg-quick"}, interfaces=[interface()], routes=[{"dev": "wg0"}],
            handshakes={"wg0": True}, internet=True,
        )
        system.diagnostic_result = {
            "ping": {"target": "1.1.1.1", "averageMs": 38, "packetLoss": 0},
            "dns": {"success": True, "durationMs": 4},
            "http": {"success": True, "statusCode": 200, "durationMs": 12},
            "externalIp": "203.0.113.10",
        }
        monitor = VpnMonitor(system)

        monitor.connectivity()
        status = monitor.status_for("wireguard")

        self.assertEqual(status["diagnostics"]["pingMs"], 38)
        self.assertEqual(status["diagnostics"]["packetLoss"], 0)
        self.assertTrue(status["diagnostics"]["dns"]["success"])

    def test_active_throne_diagnostics_are_forced_through_its_local_vpn_proxy(self):
        system = FakeSystem(
            executables={"Throne": "/usr/bin/Throne"},
            processes={"Throne", "ThroneCore"},
            interfaces=[interface("throne-tun", ip="172.19.0.1/24")],
            routes=[{"dev": "throne-tun", "dst": "172.19.0.0/24"}], internet=True,
        )
        system.diagnostic_result = {
            "ping": {"target": "https://www.cloudflare.com/cdn-cgi/trace", "averageMs": 221, "packetLoss": None},
            "dns": {"success": True, "viaVpn": True},
            "http": {"success": True, "passed": 3, "total": 3, "viaVpn": True, "targets": []},
            "externalIp": "203.0.113.10",
        }

        result = VpnMonitor(system).connectivity()

        self.assertTrue(result["viaVpn"])
        self.assertEqual(system.connectivity_requests, [("throne-tun", "socks5h://127.0.0.1:2080")])

    def test_active_throne_status_resolves_public_identity_through_the_vpn_proxy(self):
        system = FakeSystem(
            executables={"Throne": "/usr/bin/Throne"},
            processes={"Throne", "ThroneCore"},
            interfaces=[interface("throne-tun", ip="172.19.0.1/24")],
            routes=[{"dev": "throne-tun", "dst": "172.19.0.0/24"}], internet=True,
        )

        VpnMonitor(system).status_for("throne")

        self.assertIn(("throne-tun", "socks5h://127.0.0.1:2080"), system.identity_requests)

    def test_diagnostics_from_one_vpn_are_not_shown_for_another_client(self):
        system = FakeSystem(
            executables={"openvpn": "/usr/bin/openvpn", "Throne": "/usr/bin/Throne"},
            processes={"openvpn", "Throne", "ThroneCore"},
            interfaces=[interface("throne-tun", ip="172.19.0.1/24")],
            routes=[{"dev": "throne-tun", "dst": "default"}], internet=True,
        )
        system.diagnostic_result = {
            "ping": {"target": "https://www.cloudflare.com/cdn-cgi/trace", "averageMs": 38, "packetLoss": 0},
            "dns": {"success": True}, "http": {"success": True}, "externalIp": "203.0.113.10",
        }
        monitor = VpnMonitor(system)

        monitor.connectivity()

        self.assertEqual(monitor.status_for("throne")["diagnostics"]["pingMs"], 38)
        self.assertIsNone(monitor.status_for("openvpn")["diagnostics"]["pingMs"])


class TrafficTests(unittest.TestCase):
    def test_rates_and_counter_reset_are_safe(self):
        tracker = TrafficTracker()
        self.assertEqual(tracker.update("wg0", 1000, 500, 0.0)["downloadMbps"], 0.0)
        result = tracker.update("wg0", 5000, 1500, 2.0)
        self.assertEqual(result["inputBytes"], 5000)
        self.assertAlmostEqual(result["downloadMbps"], 0.016)
        self.assertAlmostEqual(result["uploadMbps"], 0.004)
        reset = tracker.update("wg0", 10, 20, 3.0)
        self.assertEqual(reset["downloadMbps"], 0.0)
        self.assertEqual(reset["uploadMbps"], 0.0)

    def test_link_statistics_are_merged_with_interface_addresses(self):
        addresses = [{"ifname": "throne-tun", "flags": ["UP"], "addr_info": [{"family": "inet", "local": "172.19.0.1", "prefixlen": 24}]}]
        links = [{"ifname": "throne-tun", "operstate": "UNKNOWN", "stats64": {"rx": {"bytes": 5000}, "tx": {"bytes": 1200}}}]
        self.assertEqual(RealSystem.merge_interfaces(addresses, links), [{"name": "throne-tun", "kind": "", "up": True, "addresses": ["172.19.0.1/24"], "rx": 5000, "tx": 1200}])

    def test_cloudflare_trace_is_parsed_without_treating_it_as_a_vpn_interface(self):
        trace = "ip=203.0.113.10\nloc=DE\nwarp=off\n"

        self.assertEqual(RealSystem.parse_cloudflare_trace(trace), {
            "exitIp": "203.0.113.10",
            "country": "Germany",
            "countryCode": "DE",
            "flag": "\U0001f1e9\U0001f1ea",
            "usesWarp": False,
        })

    def test_missing_warp_field_is_reported_as_unknown(self):
        self.assertIsNone(RealSystem.parse_cloudflare_trace("ip=203.0.113.10\nloc=DE\n")["usesWarp"])


class SystemDiagnosticsTests(unittest.TestCase):
    def _completed(self, command, returncode=0, stdout="", stderr=""):
        return CompletedProcess(command, returncode, stdout, stderr)

    @patch("vpn_monitor.system.subprocess.run")
    def test_proxy_diagnostics_use_three_popular_http_targets_through_vpn(self, run):
        def fake_run(command, **_kwargs):
            if command[0] == "getent":
                return self._completed(command, stdout="1.1.1.1 STREAM one.one.one.one\n")
            if command[0] == "ping":
                return self._completed(command, stdout="64 bytes from 1.1.1.1: time=20.0 ms\n")
            url = command[-1]
            body = "ip=203.0.113.10\nloc=DE\nwarp=off\n" if "cloudflare.com/cdn-cgi/trace" in url else ""
            return self._completed(command, stdout=body + "\n__VPN_MONITOR__204 0.123")

        run.side_effect = fake_run
        result = RealSystem().connectivity(interface="throne-tun", proxy_url="socks5h://127.0.0.1:2080")

        curl_commands = [call.args[0] for call in run.call_args_list if call.args[0][0] == "curl"]
        self.assertEqual({command[-1] for command in curl_commands}, {
            "https://www.cloudflare.com/cdn-cgi/trace",
            "https://www.google.com/generate_204",
            "https://connectivitycheck.gstatic.com/generate_204",
        })
        self.assertTrue(all(["--proxy", "socks5h://127.0.0.1:2080"] == command[command.index("--proxy"):command.index("--proxy") + 2] for command in curl_commands))
        self.assertEqual(result["http"]["passed"], 3)
        self.assertEqual(result["http"]["total"], 3)
        self.assertTrue(result["http"]["viaVpn"])
        self.assertEqual(result["externalIp"], "203.0.113.10")

    @patch("vpn_monitor.system.subprocess.run")
    def test_interface_diagnostics_bind_icmp_and_http_to_the_vpn_device(self, run):
        def fake_run(command, **_kwargs):
            if command[0] == "ping":
                return self._completed(command, stdout="64 bytes from 1.1.1.1: time=20.0 ms\n")
            if command[0] == "getent":
                return self._completed(command, stdout="1.1.1.1 STREAM one.one.one.one\n")
            return self._completed(command, stdout="\n__VPN_MONITOR__204 0.123")

        run.side_effect = fake_run
        RealSystem().connectivity(interface="wg0")

        commands = [call.args[0] for call in run.call_args_list]
        ping_command = next(command for command in commands if command[0] == "ping")
        self.assertEqual(ping_command[ping_command.index("-I") + 1], "wg0")
        curl_commands = [command for command in commands if command[0] == "curl"]
        self.assertTrue(all(command[command.index("--interface") + 1] == "if!wg0" for command in curl_commands))

    def test_interface_bind_is_unambiguous_and_probe_inputs_are_constrained(self):
        self.assertEqual(RealSystem.curl_route_options(interface="wg0"), ["--interface", "if!wg0"])
        with self.assertRaises(ValueError):
            RealSystem.curl_route_options(interface="host!example.invalid")
        with self.assertRaises(ValueError):
            RealSystem.curl_route_options(proxy_url="socks5h://example.invalid:1080")

    def test_liveness_probe_bypasses_a_stale_successful_identity_cache(self):
        system = RealSystem()
        system._identity_cache[("throne-tun", "socks5h://127.0.0.1:2080")] = (
            time.monotonic(),
            {"exitIp": "203.0.113.10", "country": "Germany", "countryCode": "DE", "flag": "\U0001f1e9\U0001f1ea", "usesWarp": False, "online": True},
        )
        system._http_probe = lambda *_args, **_kwargs: {"success": False, "body": ""}

        self.assertFalse(system.internet_available("throne-tun", "socks5h://127.0.0.1:2080"))

    @patch.object(RealSystem, "_run")
    def test_routes_include_policy_routing_tables(self, run):
        run.return_value = []

        RealSystem().routes()

        run.assert_called_once_with(["ip", "-j", "route", "show", "table", "all"], [])

    def test_service_rejects_any_non_loopback_bind_address(self):
        for host in ("0.0.0.0", "::", "192.168.1.20", "localhost"):
            with self.assertRaises(ValueError):
                serve(host=host, port=0)

    @patch("vpn_monitor.system.subprocess.Popen")
    def test_cancelled_speed_test_kills_a_curl_process_that_ignores_terminate(self, popen):
        class StubbornProcess:
            def __init__(self): self.terminated = self.killed = False
            def poll(self): return None
            def terminate(self): self.terminated = True
            def wait(self, timeout=None):
                if not self.killed: raise TimeoutExpired(["curl"], timeout)
            def kill(self): self.killed = True

        process = StubbornProcess()
        popen.return_value = process
        cancelled = Event()
        cancelled.set()

        with self.assertRaisesRegex(RuntimeError, "cancelled"):
            RealSystem._speed_command(["curl"], cancelled)

        self.assertTrue(process.terminated)
        self.assertTrue(process.killed)


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        system = FakeSystem(executables={"wg": "/usr/bin/wg", "wg-quick": "/usr/bin/wg-quick"})
        self.app = ApiApplication(VpnMonitor(system), Path(self.temp.name) / "settings.json")

    def tearDown(self):
        self.temp.cleanup()

    def call(self, method, path, body=None):
        raw = b"" if body is None else json.dumps(body).encode()
        code, headers, output = self.app.handle(method, path, raw)
        return code, json.loads(output.decode())

    def test_smoke_health_status_and_clients_are_valid_json(self):
        for path in ("/health", "/api/v1/status", "/api/v1/vpn/clients"):
            code, payload = self.call("GET", path)
            self.assertEqual(code, 200)
            self.assertIsInstance(payload, dict)
        self.assertEqual(self.call("GET", "/health")[1], {"status": "ok"})

    def test_api_responses_are_not_cacheable(self):
        code, headers, _output = self.app.handle("GET", "/health")

        self.assertEqual(code, 200)
        self.assertEqual(headers["Cache-Control"], "no-store")

    def test_selected_client_is_validated_and_persisted(self):
        code, payload = self.call("PUT", "/api/v1/settings/selected-client", {"clientId": "wireguard"})
        self.assertEqual(code, 200)
        self.assertEqual(payload["selectedClientId"], "wireguard")
        code, payload = self.call("PUT", "/api/v1/settings/selected-client", {"clientId": "missing"})
        self.assertEqual(code, 404)
        self.assertEqual(payload["code"], "CLIENT_NOT_FOUND")

    def test_saved_selection_is_returned_when_no_vpn_is_active(self):
        self.call("PUT", "/api/v1/settings/selected-client", {"clientId": "wireguard"})
        code, payload = self.call("GET", "/api/v1/status")
        self.assertEqual(code, 200)
        self.assertEqual(payload["selectedClientId"], "wireguard")

    def test_only_installed_client_is_selected_when_no_vpn_is_active(self):
        code, payload = self.call("GET", "/api/v1/status")

        self.assertEqual(code, 200)
        self.assertEqual(payload["selectedClientId"], "wireguard")

    def test_control_endpoint_is_disabled_without_explicit_control_mode(self):
        code, payload = self.call("POST", "/api/v1/vpn/wireguard/connect", {"profileId": "example"})
        self.assertEqual(code, 409)
        self.assertEqual(payload["code"], "CONTROL_DISABLED")

    def test_unknown_client_control_endpoint_is_not_misreported_as_disabled(self):
        code, payload = self.call("POST", "/api/v1/vpn/not-a-client/connect")

        self.assertEqual(code, 404)
        self.assertEqual(payload["code"], "CLIENT_NOT_FOUND")

    def test_connection_toggle_is_decided_and_rejected_by_the_backend(self):
        code, payload = self.call("POST", "/api/v1/vpn/wireguard/toggle-connection")
        self.assertEqual(code, 409)
        self.assertEqual(payload["code"], "CONTROL_DISABLED")
        self.assertEqual(payload["action"], "connect")

    def test_unsupported_interface_toggle_is_rejected(self):
        code, payload = self.call("POST", "/api/v1/vpn/wireguard/toggle-interface")
        self.assertEqual(code, 501)
        self.assertEqual(payload["code"], "NOT_SUPPORTED")

    def test_connectivity_is_a_separate_read_only_diagnostic(self):
        self.app.monitor.system.diagnostic_result = {
            "ping": {"target": "1.1.1.1", "averageMs": 38, "packetLoss": 0},
            "dns": {"success": True, "durationMs": 4},
            "http": {"success": True, "statusCode": 200, "durationMs": 12},
            "externalIp": "203.0.113.10",
        }
        code, payload = self.call("POST", "/api/v1/diagnostics/connectivity")
        self.assertEqual(code, 200)
        self.assertEqual(payload["status"], "success")
        self.assertEqual(payload["ping"]["averageMs"], 38)
        self.assertEqual(payload["externalIp"], "203.0.113.10")

    def test_speed_test_starts_and_returns_result(self):
        system = FakeSystem(
            executables={"wg": "/usr/bin/wg", "wg-quick": "/usr/bin/wg-quick"},
            processes={"wg-quick"}, interfaces=[interface()], routes=[{"dev": "wg0"}],
            handshakes={"wg0": True}, internet=True,
        )
        system.speed_result = {"downloadMbps": 125.5, "uploadMbps": 42.25, "latencyMs": 38}
        app = ApiApplication(VpnMonitor(system), Path(self.temp.name) / "speed-settings.json")
        code, _headers, output = app.handle("POST", "/api/v1/diagnostics/speed-test")
        self.assertEqual(code, 202)
        started = json.loads(output.decode())
        test_id = started["testId"]
        result = None
        for _ in range(50):
            code, _headers, output = app.handle("GET", "/api/v1/diagnostics/speed-test/" + test_id)
            result = json.loads(output.decode())
            if result["status"] == "COMPLETED":
                break
            time.sleep(.01)
        self.assertEqual(code, 200)
        self.assertEqual(result["status"], "COMPLETED")
        self.assertEqual(result["downloadMbps"], 125.5)
        self.assertEqual(result["uploadMbps"], 42.25)
        code, _headers, output = app.handle("GET", "/api/v1/status")
        status = json.loads(output.decode())
        self.assertEqual(code, 200)
        selected = next(item for item in status["items"] if item["client"]["id"] == "wireguard")
        self.assertEqual(selected["diagnostics"]["speedTest"]["status"], "COMPLETED")

    def test_speed_test_reuses_recent_status_probe_without_rescanning(self):
        system = FakeSystem(
            executables={"wg": "/usr/bin/wg", "wg-quick": "/usr/bin/wg-quick"},
            processes={"wg-quick"}, interfaces=[interface()], routes=[{"dev": "wg0"}],
            handshakes={"wg0": True}, internet=True,
        )
        monitor = VpnMonitor(system)
        monitor.status_for("wireguard")
        with patch.object(monitor, "diagnostic_target", side_effect=AssertionError("unexpected rescan")):
            started = monitor.start_speed_test()
        self.assertIn(started["status"], ("STARTED", "RUNNING", "COMPLETED"))

    def test_speed_test_is_refused_without_one_active_vpn(self):
        code, _headers, output = self.app.handle("POST", "/api/v1/diagnostics/speed-test")
        payload = json.loads(output.decode())

        self.assertEqual(code, 409)
        self.assertEqual(payload["code"], "SPEED_TEST_REQUIRES_ACTIVE_VPN")
        self.assertEqual(self.app.monitor.system.speed_requests, [])

    def test_selection_rejects_json_values_that_are_not_objects(self):
        code, _headers, output = self.app.handle("PUT", "/api/v1/settings/selected-client", b"[]")
        payload = json.loads(output.decode())

        self.assertEqual(code, 400)
        self.assertEqual(payload["code"], "INVALID_PAYLOAD")

    def test_handler_rejects_invalid_or_oversized_content_length(self):
        for value, expected in (("not-a-number", 400), (str(16 * 1024 + 1), 413)):
            codes = []
            handler = object.__new__(make_handler(self.app))
            handler.command = "PUT"
            handler.path = "/api/v1/settings/selected-client"
            handler.headers = {"Content-Length": value, "X-Vpn-Monitor-Request": "1"}
            handler.rfile = io.BytesIO()
            handler.wfile = io.BytesIO()
            handler.send_response = lambda code: codes.append(code)
            handler.send_header = lambda _key, _value: None
            handler.end_headers = lambda: None

            handler.dispatch()

            self.assertEqual(codes, [expected])

    def test_handler_rejects_state_changing_requests_without_the_ui_header(self):
        codes = []
        handler = object.__new__(make_handler(self.app))
        handler.command = "POST"
        handler.path = "/api/v1/diagnostics/connectivity"
        handler.headers = {"Content-Length": "0"}
        handler.rfile = io.BytesIO()
        handler.wfile = io.BytesIO()
        handler.send_response = lambda code: codes.append(code)
        handler.send_header = lambda _key, _value: None
        handler.end_headers = lambda: None

        handler.dispatch()

        self.assertEqual(codes, [403])

    def test_closed_qml_client_does_not_log_or_crash_on_response_write(self):
        class ClosedClient:
            def write(self, _body):
                raise BrokenPipeError()

        handler = object.__new__(make_handler(self.app))
        handler.command = "GET"
        handler.path = "/health"
        handler.headers = {}
        handler.rfile = io.BytesIO()
        handler.wfile = ClosedClient()
        handler.send_response = lambda _code: None
        handler.send_header = lambda _key, _value: None
        handler.end_headers = lambda: None
        handler.dispatch()

    def test_handler_returns_a_generic_error_when_monitor_code_raises(self):
        class BrokenApplication:
            def handle(self, *_args):
                raise RuntimeError("private implementation detail")

        codes = []
        body = io.BytesIO()
        handler = object.__new__(make_handler(BrokenApplication()))
        handler.command = "GET"
        handler.path = "/health"
        handler.headers = {}
        handler.rfile = io.BytesIO()
        handler.wfile = body
        handler.send_response = lambda code: codes.append(code)
        handler.send_header = lambda _key, _value: None
        handler.end_headers = lambda: None

        handler.dispatch()

        self.assertEqual(codes, [500])
        self.assertEqual(json.loads(body.getvalue().decode()), {"code": "INTERNAL_ERROR"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
