"""Minimal local HTTP API routing, designed to be hosted only on localhost."""
from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path

from .core import ActiveVpnRequiredError


class ApiApplication:
    def __init__(self, monitor, settings_path, bluetooth=None):
        self.monitor = monitor
        self.settings_path = Path(settings_path) if settings_path is not None else None
        self.bluetooth = bluetooth

    @staticmethod
    def response(code, payload):
        return code, {
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-store",
        }, json.dumps(payload, ensure_ascii=False).encode()

    def save_selected_client(self, client_id):
        if self.settings_path is None:
            raise RuntimeError("settings path is not configured")
        self.settings_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.settings_path.parent, 0o700)
        descriptor, temporary_path = tempfile.mkstemp(
            prefix=".settings-", suffix=".json", dir=self.settings_path.parent,
        )
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                os.fchmod(stream.fileno(), 0o600)
                stream.write(json.dumps({"selectedClientId": client_id}) + "\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary_path, self.settings_path)
        except BaseException:
            try:
                os.unlink(temporary_path)
            except FileNotFoundError:
                pass
            raise

    def status(self):
        result = self.monitor.overall_status()
        # A single active VPN always wins; otherwise use a still-installed
        # saved choice. A stale file cannot select a removed client.
        if result["selectedClientId"] or result.get("error"):
            return result
        try:
            chosen = json.loads(self.settings_path.read_text(encoding="utf-8")).get("selectedClientId", "")
        except (OSError, json.JSONDecodeError):
            chosen = ""
        if any(item["client"]["id"] == chosen and item["client"]["installed"] for item in result["items"]):
            result["selectedClientId"] = chosen
            return result
        # Once a tunnel is disconnected, there may be no active client and no
        # saved preference yet.  A sole installed adapter is unambiguous and
        # lets the UI replace the prior CONNECTED state with DISCONNECTED and
        # the direct public identity.  Multiple installed clients deliberately
        # remain unselected for the user to choose.
        installed = [item["client"]["id"] for item in result["items"] if item["client"]["installed"]]
        if len(installed) == 1:
            result["selectedClientId"] = installed[0]
        return result

    def bluetooth_status(self):
        if self.bluetooth is None:
            return {"adapterPowered": False, "updatedAt": 0, "devices": [], "available": False}
        return self.bluetooth.snapshot()

    def handle(self, method, path, body=b""):
        if method == "GET" and path == "/health": return self.response(200, {"status": "ok"})
        if method == "GET" and path == "/api/v1/status": return self.response(200, self.status())
        if method == "POST" and path == "/api/v1/status/refresh": return self.response(200, self.status())
        if method == "GET" and path == "/api/v1/vpn/clients": return self.response(200, {"items": self.monitor.clients()})
        if method == "GET" and path == "/api/v1/bluetooth/status": return self.response(200, self.bluetooth_status())
        if method == "POST" and path == "/api/v1/diagnostics/connectivity": return self.response(200, self.monitor.connectivity())
        if method == "POST" and path == "/api/v1/diagnostics/speed-test":
            try:
                return self.response(202, self.monitor.start_speed_test())
            except ActiveVpnRequiredError:
                return self.response(409, {"code": "SPEED_TEST_REQUIRES_ACTIVE_VPN", "message": "Тест скорости доступен только при одном активном VPN-подключении"})
        speed_prefix = "/api/v1/diagnostics/speed-test/"
        if path.startswith(speed_prefix):
            suffix = path[len(speed_prefix):]
            if method == "POST" and suffix.endswith("/cancel"):
                state = self.monitor.cancel_speed_test(suffix[:-len("/cancel")])
                return self.response(200, state) if state else self.response(404, {"code": "SPEED_TEST_NOT_FOUND"})
            if method == "GET" and "/" not in suffix:
                state = self.monitor.speed_test(suffix)
                return self.response(200, state) if state else self.response(404, {"code": "SPEED_TEST_NOT_FOUND"})
        if method == "PUT" and path == "/api/v1/settings/selected-client":
            try:
                payload = json.loads(body or b"{}")
            except json.JSONDecodeError: return self.response(400, {"code": "INVALID_JSON"})
            if not isinstance(payload, dict): return self.response(400, {"code": "INVALID_PAYLOAD", "message": "JSON body must be an object"})
            client_id = payload.get("clientId", "")
            summary = next((item for item in self.monitor.clients() if item["id"] == client_id and item["installed"]), None)
            if not summary: return self.response(404, {"code": "CLIENT_NOT_FOUND", "message": "VPN-клиент не найден или не установлен"})
            self.save_selected_client(client_id)
            return self.response(200, {"selectedClientId": client_id})
        if path.startswith("/api/v1/vpn/"):
            action = path.rsplit("/", 1)[-1]
            client_id = path.split("/")[-2] if path.count("/") >= 5 else ""
            if not self.monitor.adapter(client_id):
                return self.response(404, {"code": "CLIENT_NOT_FOUND", "message": "VPN-клиент не найден или не установлен"})
            if action == "toggle-connection":
                try:
                    return self.response(409, self.monitor.toggle_connection(client_id))
                except KeyError:
                    return self.response(404, {"code": "CLIENT_NOT_FOUND", "message": "VPN-клиент не найден или не установлен"})
            if action == "toggle-interface": return self.response(501, {"code": "NOT_SUPPORTED", "message": "Управление интерфейсом выполняется самим VPN-клиентом"})
            return self.response(409, {"code": "CONTROL_DISABLED", "message": "Управляющие операции выключены: требуется явный адаптер и тестовый профиль"})
        return self.response(404, {"code": "NOT_FOUND"})
