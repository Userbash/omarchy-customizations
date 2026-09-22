"""Local-only development server for the read-only monitor API."""
from __future__ import annotations

import ipaddress
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from .api import ApiApplication
from .bluetooth import BluetoothBatteryService, BusctlTransport
from .core import VpnMonitor
from .system import RealSystem


class LocalOnlyHttpServer(ThreadingHTTPServer):
    """Bounded per-request handling for the loopback-only API."""
    allow_reuse_address = True
    daemon_threads = True
    request_queue_size = 16


def make_handler(app):
    class Handler(BaseHTTPRequestHandler):
        MAX_BODY_BYTES = 16 * 1024
        REQUEST_TIMEOUT_SECONDS = 5

        def setup(self):
            super().setup()
            self.connection.settimeout(self.REQUEST_TIMEOUT_SECONDS)

        def do_GET(self): self.dispatch()
        def do_POST(self): self.dispatch()
        def do_PUT(self): self.dispatch()
        def log_message(self, *_): pass

        def write_response(self, code, headers, body):
            self.send_response(code)
            for key, value in headers.items(): self.send_header(key, value)
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                return

        def dispatch(self):
            if self.command in ("POST", "PUT") and self.headers.get("X-Vpn-Monitor-Request") != "1":
                self.write_response(403, {"Content-Type": "application/json; charset=utf-8"}, b'{"code":"LOCAL_UI_HEADER_REQUIRED"}')
                return
            try:
                size = int(self.headers.get("Content-Length", "0"))
            except (TypeError, ValueError):
                self.write_response(400, {"Content-Type": "application/json; charset=utf-8"}, b'{"code":"INVALID_CONTENT_LENGTH"}')
                return
            if size < 0 or size > self.MAX_BODY_BYTES:
                self.write_response(413, {"Content-Type": "application/json; charset=utf-8"}, b'{"code":"REQUEST_TOO_LARGE"}')
                return
            try:
                request_body = self.rfile.read(size)
            except OSError:
                self.write_response(408, {"Content-Type": "application/json; charset=utf-8"}, b'{"code":"REQUEST_TIMEOUT"}')
                return
            try:
                code, headers, body = app.handle(self.command, self.path, request_body)
            except Exception:
                # The API is a local dashboard boundary. Never expose process
                # paths, command output or tracebacks to its callers.
                self.write_response(500, {
                    "Content-Type": "application/json; charset=utf-8",
                    "Cache-Control": "no-store",
                }, b'{"code":"INTERNAL_ERROR"}')
                return
            self.write_response(code, headers, body)
    return Handler


def serve(host="127.0.0.1", port=8765):
    try:
        address = ipaddress.ip_address(host)
    except ValueError as error:
        raise ValueError("VPN monitor host must be a numeric loopback address") from error
    if not address.is_loopback:
        raise ValueError("VPN monitor may bind only to a loopback address")
    settings = Path.home() / ".local/state/omarchy/vpn-monitor/settings.json"
    app = ApiApplication(VpnMonitor(RealSystem()), settings, bluetooth=BluetoothBatteryService(BusctlTransport()))
    LocalOnlyHttpServer((host, port), make_handler(app)).serve_forever()


if __name__ == "__main__":
    serve()
