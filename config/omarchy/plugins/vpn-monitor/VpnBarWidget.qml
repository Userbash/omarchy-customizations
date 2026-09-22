import QtQuick
import "VpnUiModel.js" as Ui

Item {
  id: root
  property var status: ({})
  readonly property string connectionState: String(status && status.connection && status.connection.state || "UNKNOWN")
  readonly property string statusLabel: connectionState
  readonly property string compactLabel: connectionState === "CONNECTED" || connectionState === "DEGRADED" ? "VPN" : "VPN—"
  readonly property color statusColor: Ui.color(connectionState)
  implicitWidth: 52
  implicitHeight: 28
}
