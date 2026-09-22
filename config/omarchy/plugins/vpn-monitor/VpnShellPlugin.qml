import QtQuick

Item {
  id: root
  property var status: ({})
  property bool opened: false
  readonly property string connectionState: String(status && status.connection && status.connection.state || "UNKNOWN")
  readonly property string barText: connectionState === "CONNECTED" || connectionState === "DEGRADED" ? "VPN" : "VPN—"
  readonly property bool hasStatus: status && status.client && status.client.id

  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }
}
