"""Narrow system boundary. Production code owns every OS interaction here."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import time
from urllib.parse import urlsplit
from dataclasses import dataclass, field


class RealSystem:
    """Read-only implementation used by the monitor service."""

    TRACE_URL = "https://www.cloudflare.com/cdn-cgi/trace"
    HTTP_TARGETS = (
        ("Cloudflare Trace", TRACE_URL),
        ("Google generate_204", "https://www.google.com/generate_204"),
        ("Google connectivity", "https://connectivitycheck.gstatic.com/generate_204"),
    )
    # Identity is shown in the bar and must follow a disconnect promptly.
    # Keep presentation probes bounded, but never reuse a success for longer
    # than one polling cycle.
    IDENTITY_CACHE_SECONDS = 2
    SERVICE_CACHE_SECONDS = 5
    _INTERFACE_NAME = re.compile(r"^[A-Za-z0-9_.:-]{1,15}$")
    _LOCAL_PROXY_SCHEMES = {"socks5", "socks5h"}
    COUNTRY_NAMES = {
        "AU": "Australia", "AT": "Austria", "BE": "Belgium", "BR": "Brazil",
        "CA": "Canada", "CH": "Switzerland", "CZ": "Czechia", "DE": "Germany",
        "DK": "Denmark", "EE": "Estonia", "ES": "Spain", "FI": "Finland",
        "FR": "France", "GB": "United Kingdom", "IE": "Ireland", "IT": "Italy",
        "JP": "Japan", "KR": "South Korea", "NL": "Netherlands", "NO": "Norway",
        "PL": "Poland", "RO": "Romania", "RU": "Russia", "SE": "Sweden",
        "SG": "Singapore", "UA": "Ukraine", "US": "United States",
    }

    def __init__(self):
        self._identity_cache = {}
        self._service_cache = (0.0, set())

    def executable(self, name):
        return name if "/" in name and os.access(name, os.X_OK) else shutil.which(name)

    def process_running(self, names):
        names = set(names)
        for pid in os.listdir("/proc"):
            if not pid.isdigit():
                continue
            try:
                with open(f"/proc/{pid}/comm", encoding="utf-8") as process_name:
                    running_name = process_name.read().strip()
                if running_name in names:
                    return True
            except OSError:
                pass
        return False

    def service_running(self, names):
        if not names:
            return False
        now = time.monotonic()
        cached_at, running = self._service_cache
        if now - cached_at >= self.SERVICE_CACHE_SECONDS:
            running = set()
            for command in (
                ["systemctl", "--no-pager", "--no-legend", "--plain", "list-units", "--type=service", "--state=running"],
                ["systemctl", "--user", "--no-pager", "--no-legend", "--plain", "list-units", "--type=service", "--state=running"],
            ):
                try:
                    result = subprocess.run(command, text=True, capture_output=True, timeout=2, check=False)
                except (OSError, subprocess.TimeoutExpired):
                    continue
                if result.returncode == 0:
                    running.update(line.split(maxsplit=1)[0] for line in result.stdout.splitlines() if line.strip())
            self._service_cache = (now, running)
        return any(
            name in running
            or (name.endswith("@") and any(unit.startswith(name) for unit in running))
            for name in names
        )

    def interfaces(self):
        addresses = self._run(["ip", "-j", "addr", "show"], [])
        links = self._run(["ip", "-j", "-s", "link", "show"], [])
        return self.merge_interfaces(addresses, links)

    @staticmethod
    def merge_interfaces(addresses, links):
        link_stats = {row.get("ifname"): row.get("stats64", {}) for row in links}
        result = []
        for row in addresses:
            stats = link_stats.get(row.get("ifname"), row.get("stats64", {}))
            result.append({
                "name": row.get("ifname", ""), "kind": row.get("linkinfo", {}).get("info_kind", ""),
                "up": "UP" in row.get("flags", []),
                "addresses": [a["local"] + "/" + str(a["prefixlen"]) for a in row.get("addr_info", []) if a.get("family") in ("inet", "inet6")],
                "rx": int(stats.get("rx", {}).get("bytes", 0)),
                "tx": int(stats.get("tx", {}).get("bytes", 0)),
            })
        return result

    def routes(self):
        # Full-tunnel clients frequently use fwmarks and a private routing
        # table. Looking only at the main table would see merely the local
        # tunnel subnet and can misclassify a working policy-routed VPN.
        return self._run(["ip", "-j", "route", "show", "table", "all"], [])

    def handshake(self, interface, binary="wg"):
        if binary not in {"wg", "awg"} or not self.executable(binary):
            return False
        result = subprocess.run([binary, "show", interface, "latest-handshakes"], text=True, capture_output=True, timeout=2, check=False)
        if result.returncode:
            return False
        return any((line.split() or ["0"])[-1] != "0" for line in result.stdout.splitlines())

    @classmethod
    def curl_route_options(cls, interface=None, proxy_url=None):
        if proxy_url:
            parsed = urlsplit(proxy_url)
            try:
                port = parsed.port
            except ValueError as error:
                raise ValueError("VPN diagnostic proxy must use a valid local port") from error
            if (
                parsed.scheme not in cls._LOCAL_PROXY_SCHEMES
                or parsed.hostname not in {"127.0.0.1", "::1"}
                or port is None
                or parsed.username is not None
                or parsed.password is not None
            ):
                raise ValueError("VPN diagnostic proxy must be an unauthenticated local SOCKS proxy")
            return ["--proxy", proxy_url]
        if interface:
            if not cls._INTERFACE_NAME.fullmatch(interface):
                raise ValueError("Invalid VPN interface name")
            # `if!` makes curl treat this input as an interface, never as a
            # hostname or source address. This prevents an accidental direct
            # probe when adapter metadata is malformed.
            return ["--interface", "if!" + interface]
        return []

    def internet_available(self, interface=None, proxy_url=None):
        # Connection classification must not reuse a past successful probe.
        # A tunnel or its local SOCKS proxy can disappear between status polls.
        return bool(self.public_identity(interface=interface, proxy_url=proxy_url, fresh=True).get("online"))

    @staticmethod
    def parse_cloudflare_trace(trace):
        fields = {}
        for line in trace.splitlines():
            key, separator, value = line.partition("=")
            if separator:
                fields[key] = value
        country_code = fields.get("loc", "").upper()
        country = RealSystem.COUNTRY_NAMES.get(country_code, country_code)
        flag = "".join(chr(127397 + ord(letter)) for letter in country_code) if len(country_code) == 2 and country_code.isalpha() else ""
        return {
            "exitIp": fields.get("ip", ""),
            "country": country,
            "countryCode": country_code,
            "flag": flag,
            "usesWarp": fields["warp"].lower() == "on" if "warp" in fields else None,
        }

    def _http_probe(self, name, url, interface=None, proxy_url=None):
        started = time.monotonic()
        command = [
            "curl", "-sS", "--connect-timeout", "2", "--max-time", "4",
            *self.curl_route_options(interface, proxy_url),
            "-o", "-", "-w", "\n__VPN_MONITOR__%{http_code} %{time_total}", url,
        ]
        try:
            response = subprocess.run(command, text=True, capture_output=True, timeout=5, check=False)
        except (OSError, subprocess.TimeoutExpired):
            response = None
        body, marker, measurement = (response.stdout if response is not None else "").rpartition("\n__VPN_MONITOR__")
        fields = measurement.strip().split()
        status_code = int(fields[0]) if fields and fields[0].isdigit() else 0
        try:
            duration_ms = round(float(fields[1]) * 1000) if len(fields) > 1 else round((time.monotonic() - started) * 1000)
        except ValueError:
            duration_ms = round((time.monotonic() - started) * 1000)
        success = response is not None and response.returncode == 0 and 200 <= status_code < 300
        return {
            "name": name, "url": url, "success": success, "statusCode": status_code,
            "durationMs": duration_ms, "viaVpn": bool(interface or proxy_url), "body": body if marker else "",
        }

    def public_identity(self, interface=None, proxy_url=None, fresh=False):
        now = time.monotonic()
        cache_key = (interface or "", proxy_url or "")
        cached = self._identity_cache.get(cache_key)
        if not fresh and cached is not None and now - cached[0] < self.IDENTITY_CACHE_SECONDS:
            return dict(cached[1])
        fallback = {"exitIp": "", "country": "", "countryCode": "", "flag": "", "usesWarp": None, "online": False}
        result = self._http_probe("Cloudflare Trace", self.TRACE_URL, interface, proxy_url)
        if result["success"]:
            fallback.update(self.parse_cloudflare_trace(result["body"]))
            fallback["online"] = True
        self._identity_cache[cache_key] = (now, fallback)
        return dict(fallback)

    def connectivity(self, interface=None, proxy_url=None):
        """Bounded read-only diagnostic; a failed probe is data, not an error."""
        import re
        started = time.monotonic()
        targets = [self._http_probe(name, url, interface, proxy_url) for name, url in self.HTTP_TARGETS]
        cloudflare = targets[0]
        identity = self.parse_cloudflare_trace(cloudflare["body"]) if cloudflare["success"] else {}
        if proxy_url:
            # SOCKS5 cannot transport ICMP. This is end-to-end HTTPS latency
            # through the remote resolver and the selected VPN proxy.
            ping = {
                "target": cloudflare["url"], "averageMs": cloudflare["durationMs"] if cloudflare["success"] else None,
                "packetLoss": 0 if cloudflare["success"] else 100, "method": "HTTPS via SOCKS5", "viaVpn": True,
            }
            dns = {"success": cloudflare["success"], "durationMs": cloudflare["durationMs"], "method": "SOCKS5 remote DNS", "viaVpn": True}
        else:
            command = ["ping", "-n", "-c", "1", "-W", "2"]
            if interface:
                command += ["-I", interface]
            command.append("1.1.1.1")
            try:
                icmp = subprocess.run(command, text=True, capture_output=True, timeout=3, check=False)
            except (OSError, subprocess.TimeoutExpired):
                icmp = None
            match = re.search(r"time=([0-9.]+) ?ms", icmp.stdout if icmp else "")
            ping = {"target": "1.1.1.1", "averageMs": float(match.group(1)) if match else None,
                    "packetLoss": 0 if icmp is not None and icmp.returncode == 0 else 100,
                    "method": "ICMP bound interface" if interface else "ICMP", "viaVpn": bool(interface)}
            dns_start = time.monotonic()
            try:
                lookup = subprocess.run(["getent", "ahostsv4", "one.one.one.one"], text=True, capture_output=True, timeout=3, check=False)
                dns_success = lookup.returncode == 0 and bool(lookup.stdout.strip())
            except (OSError, subprocess.TimeoutExpired):
                dns_success = False
            # getent has no interface binding. It remains useful as a local
            # resolver health signal but must never be presented as proof
            # that DNS travelled through a split tunnel.
            dns = {"success": dns_success, "durationMs": round((time.monotonic() - dns_start) * 1000), "method": "system resolver (not route-pinned)", "viaVpn": False}
        passed = sum(1 for item in targets if item["success"])
        return {
            "ping": ping, "dns": dns,
            "http": {"success": passed == len(targets), "passed": passed, "total": len(targets), "targets": [{key: value for key, value in item.items() if key != "body"} for item in targets], "viaVpn": bool(interface or proxy_url)},
            "externalIp": identity.get("exitIp", ""),
            "server": {key: identity.get(key, "" if key != "usesWarp" else None) for key in ("country", "countryCode", "flag", "usesWarp")},
            "viaVpn": bool(interface or proxy_url), "interface": interface or "", "probeDurationMs": round((time.monotonic() - started) * 1000),
        }

    @staticmethod
    def _speed_command(command, cancelled):
        process = subprocess.Popen(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        while process.poll() is None:
            if cancelled.is_set():
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=2)
                raise RuntimeError("Speed test cancelled")
            time.sleep(.1)
        output, error = process.communicate()
        if process.returncode:
            raise RuntimeError(error.strip() or "Speed test request failed")
        try: return float(output.strip()) * 8 / 1_000_000
        except ValueError as error: raise RuntimeError("Speed test returned no measurement") from error

    def speed_test(self, cancelled, interface=None, proxy_url=None):
        if not self.executable("curl"):
            raise RuntimeError("curl is not available")
        # Throne's local SOCKS5 proxy can intermittently terminate the TLS
        # handshake when curl negotiates HTTP/2.  The speed endpoint does not
        # need HTTP/2, so keep both phases on the more interoperable protocol.
        common = ["curl", "-fsSL", "--http1.1", "--connect-timeout", "4", "--max-time", "20", *self.curl_route_options(interface, proxy_url), "-o", "/dev/null", "-w"]
        download = self._speed_command(common + ["%{speed_download}", "https://speed.cloudflare.com/__down?bytes=5000000"], cancelled)
        if cancelled.is_set(): raise RuntimeError("Speed test cancelled")
        with tempfile.NamedTemporaryFile() as payload:
            payload.write(os.urandom(1_000_000))
            payload.flush()
            upload = self._speed_command(common + ["%{speed_upload}", "--data-binary", "@" + payload.name, "https://speed.cloudflare.com/__up"], cancelled)
        latency = self.connectivity(interface=interface, proxy_url=proxy_url)["ping"]["averageMs"]
        return {"downloadMbps": round(download, 2), "uploadMbps": round(upload, 2), "latencyMs": latency}

    @staticmethod
    def _run(command, fallback):
        try:
            result = subprocess.run(command, text=True, capture_output=True, timeout=3, check=False)
            return json.loads(result.stdout) if result.returncode == 0 else fallback
        except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
            return fallback


@dataclass
class FakeSystem:
    """Deterministic test double; never calls a real executable."""
    executables: dict = field(default_factory=dict)
    processes: set = field(default_factory=set)
    services: set = field(default_factory=set)
    interfaces_data: list = field(default_factory=list, metadata={"name": "interfaces"})
    routes_data: list = field(default_factory=list, metadata={"name": "routes"})
    handshakes: dict = field(default_factory=dict)
    internet: bool = False

    def __init__(self, executables=None, processes=None, services=None, interfaces=None, routes=None, handshakes=None, internet=False, identity=None):
        self.executables = executables or {}
        self.processes = set(processes or ())
        self.services = set(services or ())
        self.interfaces_data = list(interfaces or ())
        self.routes_data = list(routes or ())
        self.handshakes = handshakes or {}
        self.internet = internet
        self.identity = identity or {"exitIp": "", "country": "", "countryCode": "", "flag": "", "usesWarp": None}
        self.identity_requests, self.connectivity_requests, self.speed_requests = [], [], []

    def executable(self, name): return self.executables.get(name)
    def process_running(self, names): return bool(set(names) & self.processes)
    def service_running(self, names):
        return any(
            name in self.services
            or (name.endswith("@") and any(unit.startswith(name) for unit in self.services))
            for name in names
        )
    def interfaces(self): return self.interfaces_data
    def routes(self): return self.routes_data
    def handshake(self, interface, binary="wg"): return bool(self.handshakes.get(interface))
    def internet_available(self, interface=None, proxy_url=None): return self.internet
    def public_identity(self, interface=None, proxy_url=None, fresh=False):
        self.identity_requests.append((interface, proxy_url))
        return dict(self.identity)
    def speed_test(self, cancelled, interface=None, proxy_url=None):
        self.speed_requests.append((interface, proxy_url))
        if cancelled.is_set(): raise RuntimeError("Speed test cancelled")
        return getattr(self, "speed_result", {"downloadMbps": 0.0, "uploadMbps": 0.0, "latencyMs": None})
    def connectivity(self, interface=None, proxy_url=None):
        self.connectivity_requests.append((interface, proxy_url))
        return getattr(self, "diagnostic_result", {"ping": {"target": "1.1.1.1", "averageMs": None, "packetLoss": 100}, "dns": {"success": self.internet, "durationMs": None}, "http": {"success": self.internet, "statusCode": 200 if self.internet else 0, "durationMs": None}, "externalIp": ""})
