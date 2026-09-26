"""Pure detection/state logic. It does not issue VPN-control commands."""
from __future__ import annotations

from dataclasses import dataclass
from time import monotonic
from threading import Event, Lock, Thread
from uuid import uuid4

CLIENT_NOT_INSTALLED = "NOT_INSTALLED"
CLIENT_INSTALLED_STOPPED = "INSTALLED_STOPPED"
CLIENT_STARTING = "STARTING"
CLIENT_RUNNING = "RUNNING"
CLIENT_STOPPING = "STOPPING"
CLIENT_ERROR = "ERROR"
CONNECTION_DISCONNECTED = "DISCONNECTED"
CONNECTION_CONNECTING = "CONNECTING"
CONNECTION_CONNECTED = "CONNECTED"
CONNECTION_DISCONNECTING = "DISCONNECTING"
CONNECTION_DEGRADED = "DEGRADED"
CONNECTION_ERROR = "ERROR"
CONNECTION_UNKNOWN = "UNKNOWN"


@dataclass(frozen=True)
class Adapter:
    id: str
    name: str
    executables: tuple
    processes: tuple
    interface_prefixes: tuple
    generic_interface_prefixes: tuple = ()
    interface_kind: str = ""
    supports_handshake: bool = False
    handshake_binary: str = ""
    profiles: tuple = ()
    diagnostic_proxy: str = ""
    requires_process: bool = True
    excluded_interface_prefixes: tuple = ()
    services: tuple = ()

    @property
    def capabilities(self):
        # Discovery is safe by default. Control adapters must be explicitly
        # installed/configured before mutation endpoints can be enabled.
        return {"start": False, "stop": False, "connect": False, "disconnect": False,
                "toggleInterface": False, "ping": True, "speedTest": True}

    def installed(self, system):
        # Kernel-managed WireGuard/AmneziaWG interfaces can survive after the
        # helper CLI was removed. A matching process is likewise evidence that
        # a client is present even when its launcher is no longer on PATH.
        return (
            any(system.executable(exe) for exe in self.executables)
            or system.process_running(self.processes)
            or system.service_running(self.services)
            or (not self.requires_process and bool(self.strict_matching_interfaces(system)))
        )

    def service_running(self, system):
        return system.service_running(self.services)

    def running(self, system):
        return system.process_running(self.processes) or self.service_running(system)

    def strict_matching_interfaces(self, system):
        rows = []
        for row in system.interfaces():
            name, kind = row.get("name", ""), row.get("kind", "")
            matches_name = name.startswith(self.interface_prefixes)
            matches_kind = self.interface_kind and kind == self.interface_kind
            excluded = name.startswith(self.excluded_interface_prefixes)
            if not excluded and (matches_name or matches_kind):
                rows.append(row)
        return rows

    def generic_matching_interfaces(self, system):
        if not self.generic_interface_prefixes:
            return []
        return [
            row for row in system.interfaces()
            if row.get("name", "").startswith(self.generic_interface_prefixes)
            and not row.get("name", "").startswith(self.excluded_interface_prefixes)
        ]


ADAPTERS = (
    Adapter("wireguard", "WireGuard", ("wg", "wg-quick"), ("wg-quick", "wireguard"), ("wg",), (), "wireguard", True, "wg",
            requires_process=False, excluded_interface_prefixes=("awg", "amneziawg", "warp", "CloudflareWARP", "cloudflare-warp", "throne-"), services=("wg-quick@",)),
    Adapter("openvpn", "OpenVPN", ("openvpn", "openvpn3"), ("openvpn", "openvpn3-service", "openvpn3-session"), (), ("tun", "tap"),
            services=("openvpn.service", "openvpn-client@", "openvpn-server@")),
    Adapter("amnezia", "AmneziaVPN", ("amnezia-vpn", "AmneziaVPN"), ("amnezia-vpn", "AmneziaVPN"), ("amnezia",), ("tun", "tap")),
    Adapter("amneziawg", "AmneziaWG", ("awg", "awg-quick"), ("awg-quick", "amneziawg"), ("awg", "amneziawg"), (), "", True, "awg",
            requires_process=False),
    Adapter("outline", "Outline", ("outline-client", "Outline-Client"), ("outline-client", "Outline-Client"), ("outline",), ("tun", "tap")),
    Adapter("cloudflare-warp", "Cloudflare WARP", ("warp-cli", "warp-svc"), ("warp-svc",), ("warp", "CloudflareWARP", "cloudflare-warp"),
            services=("warp-svc.service",)),
    # Installed locally outside PATH. This adapter is deliberately monitor-only:
    # the public client does not provide a documented CLI control contract.
    # Throne exposes a local SOCKS5 proxy while its TUN contains only private
    # routes. Diagnostics must use that proxy or they would bypass the VPN.
    # Throne is discovered through PATH/process metadata. A machine-specific
    # absolute executable path would make this repository non-portable.
    Adapter("throne", "Throne", ("Throne", "ThroneCore"), ("Throne", "ThroneCore"), ("throne-tun",), diagnostic_proxy="socks5h://127.0.0.1:2080"),
)


class TrafficTracker:
    def __init__(self): self.previous = {}

    def update(self, name, rx, tx, now=None):
        now = monotonic() if now is None else now
        prior = self.previous.get(name)
        download = upload = 0.0
        if prior:
            old_rx, old_tx, old_now = prior
            seconds = now - old_now
            if seconds > 0 and rx >= old_rx and tx >= old_tx:
                download = (rx - old_rx) * 8 / 1_000_000 / seconds
                upload = (tx - old_tx) * 8 / 1_000_000 / seconds
        self.previous[name] = (rx, tx, now)
        return {"inputBytes": max(0, rx), "outputBytes": max(0, tx), "downloadMbps": download, "uploadMbps": upload}


class SpeedTestManager:
    """Runs a bounded diagnostic in the background; it never controls a VPN."""
    MAX_HISTORY = 32

    def __init__(self, system):
        self.system, self.lock, self.tests, self.cancel_events = system, Lock(), {}, {}

    def _prune(self):
        terminal = {"COMPLETED", "ERROR", "CANCELLED"}
        completed = [key for key, value in self.tests.items() if value["status"] in terminal]
        while len(self.tests) > self.MAX_HISTORY and completed:
            old = completed.pop(0)
            self.tests.pop(old, None)
            self.cancel_events.pop(old, None)

    def start(self, interface=None, proxy_url=None):
        with self.lock:
            self._prune()
            running = next((item for item in self.tests.values() if item["status"] in ("STARTED", "RUNNING", "CANCELLING")), None)
            if running:
                return dict(running)
            test_id = "speed-" + uuid4().hex
            record = {"testId": test_id, "status": "STARTED", "progress": 0}
            self.tests[test_id] = record
            cancelled = Event()
            self.cancel_events[test_id] = cancelled
        Thread(target=self._run, args=(test_id, cancelled, interface, proxy_url), daemon=True).start()
        return dict(record)

    def _run(self, test_id, cancelled, interface, proxy_url):
        with self.lock:
            self.tests[test_id].update(status="RUNNING", progress=10)
        try:
            result = self.system.speed_test(cancelled, interface=interface, proxy_url=proxy_url)
            with self.lock:
                record = self.tests[test_id]
                if cancelled.is_set():
                    record.update(status="CANCELLED", progress=0)
                else:
                    record.update(status="COMPLETED", progress=100, **result)
                self._prune()
        except Exception as error:
            with self.lock:
                record = self.tests[test_id]
                record.update(status="CANCELLED" if cancelled.is_set() else "ERROR", progress=0)
                if not cancelled.is_set(): record["message"] = str(error)
                self._prune()

    def get(self, test_id):
        with self.lock:
            return dict(self.tests[test_id]) if test_id in self.tests else None

    def current(self):
        with self.lock:
            return dict(next(reversed(self.tests.values()))) if self.tests else {"status": "IDLE"}

    def cancel(self, test_id):
        with self.lock:
            record = self.tests.get(test_id)
            if not record: return None
            if record["status"] in ("COMPLETED", "ERROR", "CANCELLED"): return dict(record)
            self.cancel_events[test_id].set()
            record.update(status="CANCELLING")
            return dict(record)


class ActiveVpnRequiredError(RuntimeError):
    """Raised when a diagnostic would otherwise leave through the direct route."""


class VpnMonitor:
    def __init__(self, system, adapters=ADAPTERS):
        self.system, self.adapters, self.traffic = system, adapters, TrafficTracker()
        self.last_diagnostics = {"clients": {}, "direct": {}}
        self.speed_tests = SpeedTestManager(system)
        self._recent_target = None
        self._recent_target_at = 0.0

    def adapter(self, client_id):
        return next((a for a in self.adapters if a.id == client_id), None)

    def clients(self):
        return [self.client_summary(adapter) for adapter in self.adapters]

    def interfaces_for(self, adapter, running=None):
        """Return interfaces with a defensible owner attribution.

        Names such as ``tun0`` and ``tap0`` are transport primitives, not
        client identities. They are admitted only when exactly one running
        adapter could own them. Strong client-specific names always win.
        """
        strict = adapter.strict_matching_interfaces(self.system)
        if strict:
            return strict
        if running is None:
            running = adapter.running(self.system)
        if not running:
            return []
        candidates = adapter.generic_matching_interfaces(self.system)
        claimed = []
        for iface in candidates:
            owners = [
                candidate for candidate in self.adapters
                if candidate.running(self.system)
                and any(item.get("name") == iface.get("name") for item in candidate.generic_matching_interfaces(self.system))
            ]
            if len(owners) == 1 and owners[0].id == adapter.id:
                claimed.append(iface)
        return claimed

    def _route_exists(self, interface_name):
        return any(
            route.get("dev") == interface_name
            and route.get("type", "unicast") not in {"local", "broadcast", "multicast", "unreachable", "blackhole", "prohibit", "throw"}
            for route in self.system.routes()
        )

    def interface_for(self, adapter, running):
        interfaces = self.interfaces_for(adapter, running)
        if not interfaces:
            return None
        # A route is a stronger signal than source ordering from netlink.
        return max(
            interfaces,
            key=lambda iface: (
                bool(iface.get("up")), bool(iface.get("addresses")),
                self._route_exists(iface.get("name", "")),
            ),
        )

    def client_summary(self, adapter):
        installed = adapter.installed(self.system)
        running = installed and adapter.running(self.system)
        connection = self.connection(adapter, installed, running)
        return {"id": adapter.id, "name": adapter.name, "installed": installed, "running": running or connection["active"],
                "connected": connection["state"] in (CONNECTION_CONNECTED, CONNECTION_DEGRADED),
                "supported": True, "confidence": 1.0 if installed else 0.0, "capabilities": adapter.capabilities}

    @staticmethod
    def probe_context(adapter, iface):
        return {
            "interface": iface["name"] if iface else None,
            "proxy_url": adapter.diagnostic_proxy or None,
        }

    def status_for(self, client_id):
        adapter = self.adapter(client_id)
        if not adapter: raise KeyError(client_id)
        installed = adapter.installed(self.system)
        process_running = installed and self.system.process_running(adapter.processes)
        service_running = installed and adapter.service_running(self.system)
        running = process_running or service_running
        iface = self.interface_for(adapter, running)
        conn = self.connection(adapter, installed, running, iface)
        if conn["active"] and iface:
            self._recent_target = (adapter, iface)
            self._recent_target_at = monotonic()
        probe = self.probe_context(adapter, iface)
        # The dashboard must always expose a real public identity.  When a
        # tunnel is inactive this deliberately bypasses the adapter's VPN
        # binding/proxy and reports the direct network identity instead.
        identity_probe = probe if conn["active"] else {"interface": None, "proxy_url": None}
        identity = self.system.public_identity(**identity_probe)
        diagnostics = self.diagnostics_for(adapter, conn)
        return {
            "client": {"id": adapter.id, "name": adapter.name, "installed": installed, "processRunning": process_running,
                       "serviceRunning": service_running,
                       "state": CLIENT_RUNNING if running or conn["active"] else (CLIENT_INSTALLED_STOPPED if installed else CLIENT_NOT_INSTALLED)},
            "connection": conn,
            "interface": self.interface_state(iface),
            "server": {
                "name": "", "country": identity.get("country", ""), "countryCode": identity.get("countryCode", ""),
                "flag": identity.get("flag", ""), "city": "", "exitIp": identity.get("exitIp", ""),
                "usesWarp": identity.get("usesWarp"),
                "viaVpn": conn["active"],
            },
            "diagnostics": {
                "internetAvailable": self.system.internet_available(**probe) if iface else False,
                "pingMs": diagnostics.get("pingMs"), "packetLoss": diagnostics.get("packetLoss"),
                "dns": diagnostics.get("dns"), "http": diagnostics.get("http"),
                "viaVpn": diagnostics.get("viaVpn"),
                "interface": diagnostics.get("interface"),
                "speedTest": self.speed_tests.current(),
            },
            "traffic": self.traffic.update(iface["name"], int(iface.get("rx", 0)), int(iface.get("tx", 0))) if iface else {"inputBytes": 0, "outputBytes": 0, "downloadMbps": 0.0, "uploadMbps": 0.0},
            "capabilities": adapter.capabilities,
        }

    def interface_state(self, iface):
        if not iface: return {"name": "", "type": "", "state": "NOT_FOUND", "ip": ""}
        return {"name": iface["name"], "type": iface.get("kind", ""), "state": "UP" if iface.get("up") else "DOWN", "ip": (iface.get("addresses") or [""])[0]}

    def diagnostics_for(self, adapter, connection):
        if connection["active"]:
            return self.last_diagnostics["clients"].get(adapter.id, {})
        # A direct diagnostic has no VPN attribution. It is only relevant
        # while there is no active tunnel at all, never as another client's
        # apparent result.
        if not self.last_diagnostics["clients"]:
            return self.last_diagnostics["direct"]
        return {}

    def connection(self, adapter, installed, running, iface=None):
        if not installed: return {"state": CONNECTION_UNKNOWN, "active": False, "profileId": ""}
        if adapter.requires_process and not running:
            return {"state": CONNECTION_DISCONNECTED, "active": False, "profileId": ""}
        iface = iface if iface is not None else self.interface_for(adapter, running)
        if not iface or not iface.get("up") or not iface.get("addresses"):
            return {"state": CONNECTION_DISCONNECTED, "active": False, "profileId": ""}
        # A split-tunnel client can route only private CIDRs over VPN, whereas
        # a full tunnel carries the default route. Either is a VPN route.
        route_ok = self._route_exists(iface["name"])
        if not route_ok:
            return {"state": CONNECTION_DEGRADED, "active": True, "profileId": ""}
        probe = self.probe_context(adapter, iface)
        internet_ok = self.system.internet_available(**probe)
        # A successful traffic probe bound to this interface (or through the
        # client's fixed local proxy) is a stronger liveness signal than a
        # historic handshake. Handshake data is still queried for adapters
        # that expose it, but an unavailable helper must not hide a working
        # kernel tunnel.
        if adapter.supports_handshake:
            self.system.handshake(iface["name"], adapter.handshake_binary)
        return {"state": CONNECTION_CONNECTED if internet_ok else CONNECTION_DEGRADED, "active": True, "profileId": ""}

    def overall_status(self):
        items = [self.status_for(a.id) for a in self.adapters]
        active = [item["client"]["id"] for item in items if item["connection"]["active"]]
        result = {"items": items, "selectedClientId": active[0] if len(active) == 1 else ""}
        if len(active) > 1:
            result["error"] = {"code": "MULTIPLE_ACTIVE_VPN_CONNECTIONS", "message": "Обнаружено несколько активных VPN-подключений", "clients": active}
        return result

    def diagnostic_target(self):
        active = []
        for adapter in self.adapters:
            installed = adapter.installed(self.system)
            running = installed and adapter.running(self.system)
            iface = self.interface_for(adapter, running)
            if self.connection(adapter, installed, running, iface)["active"]:
                active.append((adapter, iface))
        return active[0] if len(active) == 1 else (None, None)

    def connectivity(self):
        adapter, iface = self.diagnostic_target()
        probe = self.probe_context(adapter, iface) if adapter else {"interface": None, "proxy_url": None}
        result = self.system.connectivity(**probe)
        result["viaVpn"] = bool(adapter)
        result["interface"] = probe["interface"] or ""
        ping_ok = result.get("ping", {}).get("averageMs") is not None
        result["status"] = "success" if ping_ok and result.get("dns", {}).get("success") and result.get("http", {}).get("success") else "partial"
        diagnostic_state = {
            "pingMs": result.get("ping", {}).get("averageMs"),
            "packetLoss": result.get("ping", {}).get("packetLoss"),
            "dns": result.get("dns"), "http": result.get("http"),
            "viaVpn": result["viaVpn"], "interface": result["interface"],
        }
        if adapter:
            self.last_diagnostics["clients"][adapter.id] = diagnostic_state
        else:
            self.last_diagnostics["direct"] = diagnostic_state
        return result

    def start_speed_test(self):
        # Status is polled every two seconds. Reuse its fresh, already
        # validated target so a speed-test click does not repeat the full
        # process/interface/route scan before returning STARTED.
        if self._recent_target and monotonic() - self._recent_target_at <= 3.0:
            adapter, iface = self._recent_target
        else:
            adapter, iface = self.diagnostic_target()
        if adapter is None:
            raise ActiveVpnRequiredError("Speed test requires exactly one active VPN connection")
        probe = self.probe_context(adapter, iface)
        return self.speed_tests.start(**probe)
    def speed_test(self, test_id): return self.speed_tests.get(test_id)
    def cancel_speed_test(self, test_id): return self.speed_tests.cancel(test_id)

    def toggle_connection(self, client_id):
        adapter = self.adapter(client_id)
        if not adapter:
            raise KeyError(client_id)
        state = self.status_for(client_id)["connection"]
        action = "disconnect" if state["active"] else "connect"
        return {
            "code": "CONTROL_DISABLED",
            "action": action,
            "message": "Управление VPN недоступно: для этого клиента не настроен безопасный control-adapter",
        }
