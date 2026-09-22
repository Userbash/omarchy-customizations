.pragma library

function safe(value, fallback) { return value === undefined || value === null ? fallback : value }

function buttons(status) {
  status = safe(status, {})
  var client = safe(status.client, {})
  var connection = safe(status.connection, {})
  var caps = safe(status.capabilities, {})
  var busy = safe(status.busy, false)
  var installed = client.state !== "NOT_INSTALLED"
  var running = client.state === "RUNNING"
  var connected = connection.state === "CONNECTED"
  var connecting = connection.state === "CONNECTING" || connection.state === "DISCONNECTING"
  if (busy) connecting = true
  return {
    start: !busy && installed && !running && !!caps.start,
    stop: !busy && running && !connecting && !!caps.stop,
    connect: !busy && running && connection.state === "DISCONNECTED" && !!caps.connect,
    disconnect: !busy && connected && !!caps.disconnect,
    ping: !busy && installed && !!caps.ping,
    speedTest: !busy && connected && !!caps.speedTest,
    toggleInterface: !busy && !!caps.toggleInterface
  }
}

function label(value) {
  return ({ CONNECTED: "Подключено", CONNECTING: "Подключение…", DISCONNECTING: "Отключение…", DISCONNECTED: "Отключено", DEGRADED: "Соединение неисправно", ERROR: "Ошибка", UNKNOWN: "Неизвестно" })[value] || "Неизвестно"
}

function color(value) {
  if (value === "CONNECTED") return "#e06c75"
  if (value === "CONNECTING" || value === "DISCONNECTING" || value === "DEGRADED") return "#e5b567"
  if (value === "ERROR") return "#e06c75"
  if (value === "DISCONNECTED") return "#78c379"
  return "#a8b0b8"
}

function mainAction(status) {
  status = safe(status, {})
  var connection = safe(status.connection, {})
  var caps = safe(status.capabilities, {})
  var state = String(safe(connection.state, "UNKNOWN"))
  if (state === "CONNECTED") return { text: "Disconnect", action: "disconnect", enabled: !!caps.disconnect, kind: "danger" }
  if (state === "DISCONNECTED") return { text: "Connect", action: "connect", enabled: !!caps.connect, kind: "success" }
  if (state === "CONNECTING") return { text: "Cancel", action: "disconnect", enabled: false, kind: "secondary" }
  if (state === "ERROR") return { text: "Retry", action: "connect", enabled: !!caps.connect, kind: "success" }
  return { text: "Refresh", action: "refresh", enabled: true, kind: "secondary" }
}

function latencyLabel(value) {
  if (value === undefined || value === null || isNaN(Number(value))) return "Not tested"
  value = Number(value)
  if (value <= 50) return "Good"
  if (value <= 100) return "Normal"
  if (value <= 200) return "High"
  return "Critical"
}

function formatBytes(value) {
  value = Number(value)
  if (!isFinite(value) || value < 0) return "—"
  var units = ["B", "KB", "MB", "GB", "TB"], i = 0
  while (value >= 1024 && i < units.length - 1) { value /= 1024; i++ }
  return (i === 0 ? String(Math.round(value)) : value.toFixed(2)) + " " + units[i]
}

function gridColumns(width) { return Number(width) <= 620 ? 1 : 2 }

if (typeof module !== "undefined") module.exports = { buttons: buttons, label: label, color: color, mainAction: mainAction, latencyLabel: latencyLabel, formatBytes: formatBytes, gridColumns: gridColumns }
