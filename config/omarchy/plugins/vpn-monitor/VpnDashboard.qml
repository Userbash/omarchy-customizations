import QtQuick
import "VpnUiModel.js" as Ui

pragma ComponentBehavior: Bound

Item {
  id: root

  property var status: ({})
  property real availableWidth: width > 0 ? width : 920
  property bool reducedMotion: false
  signal actionRequested(string action)

  readonly property var client: status && status.client ? status.client : ({})
  readonly property var connection: status && status.connection ? status.connection : ({})
  readonly property var iface: status && status.interface ? status.interface : ({})
  readonly property var server: status && status.server ? status.server : ({})
  readonly property var diagnostics: status && status.diagnostics ? status.diagnostics : ({})
  readonly property var traffic: status && status.traffic ? status.traffic : ({})
  readonly property var capabilities: status && status.capabilities ? status.capabilities : ({})
  readonly property int gridColumns: Ui.gridColumns(availableWidth)
  readonly property real gridGap: gridColumns === 1 ? 12 : 18
  readonly property real gridTileWidth: gridColumns === 1 ? implicitWidth : (implicitWidth - gridGap) / 2
  readonly property string connectionState: String(connection.state || "UNKNOWN")
  readonly property string connectionLabel: connectionState
  readonly property var primaryAction: Ui.mainAction({ connection: connection, capabilities: capabilities })
  readonly property string mainActionText: primaryAction.text
  readonly property var pingValue: diagnostics.pingMs
  readonly property string latencyText: pingValue === undefined || pingValue === null ? "— ms" : Math.round(Number(pingValue)) + " ms"
  readonly property string networkText: traffic.downloadMbps === undefined || traffic.downloadMbps === null || traffic.uploadMbps === undefined || traffic.uploadMbps === null ? "— / —" : "↓ " + Number(traffic.downloadMbps).toFixed(2) + "  ↑ " + Number(traffic.uploadMbps).toFixed(2) + " Mbps"

  implicitWidth: Math.min(920, availableWidth)
  implicitHeight: dashboard.implicitHeight

  component GlassTile: Rectangle {
    id: glassTile

    required property string title
    property int tileHeight: 144
    objectName: "vpnTile_" + title.replace(/[^A-Za-z0-9]/g, "_")
    implicitHeight: tileHeight
    height: tileHeight
    radius: root.gridColumns === 1 ? 24 : 30
    color: "#3F8EAAB9"
    border.width: 1
    border.color: "#66FFFFFF"
    gradient: Gradient {
      GradientStop { position: 0; color: "#72E2EFF5" }
      GradientStop { position: .40; color: "#3D8EAAB9" }
      GradientStop { position: 1; color: "#365D768D" }
    }
    transform: Translate { id: entranceOffset; y: 0 }
    opacity: 0
    Component.onCompleted: entrance.start()

    ParallelAnimation {
      id: entrance
      NumberAnimation { target: glassTile; property: "opacity"; to: 1; duration: root.reducedMotion ? 0 : 300; easing.type: Easing.OutCubic }
      NumberAnimation { target: entranceOffset; property: "y"; from: 8; to: 0; duration: root.reducedMotion ? 0 : 360; easing.type: Easing.OutCubic }
    }

    Rectangle { anchors.fill: parent; anchors.margins: 1; radius: parent.radius - 1; color: "transparent"; border.width: 1; border.color: "#3DFFFFFF" }
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: parent.height * .42
      radius: parent.radius
      gradient: Gradient {
        GradientStop { position: 0; color: "#42FFFFFF" }
        GradientStop { position: 1; color: "transparent" }
      }
    }
    Text { x: 24; y: 20; text: parent.title; color: "#C8FFFFFF"; font.family: "Noto Sans"; font.pixelSize: 11; font.bold: true; font.letterSpacing: .12 }
  }

  component GlassButton: Rectangle {
    required property string text
    required property string action

    objectName: "vpnAction_" + action
    property bool enabledAction: false
    property string kind: "secondary"
    implicitWidth: buttonText.implicitWidth + 30
    implicitHeight: 42
    radius: 21
    color: kind === "danger" ? "#42E77979" : (kind === "success" ? "#4290D9AE" : "#3CFFFFFF")
    border.width: 1
    border.color: "#52FFFFFF"
    opacity: enabledAction ? 1 : .46
    scale: pressArea.pressed && enabledAction ? .97 : 1
    Behavior on scale { NumberAnimation { duration: root.reducedMotion ? 0 : 120 } }

    Text { id: buttonText; anchors.centerIn: parent; text: parent.text; color: "#F7FFFFFF"; font.family: "Noto Sans"; font.pixelSize: 12; font.bold: true }
    MouseArea {
      id: pressArea
      objectName: "vpnActionArea_" + parent.action
      anchors.fill: parent
      enabled: parent.enabledAction
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.actionRequested(parent.action)
    }
    Keys.onReturnPressed: if (enabledAction) root.actionRequested(action)
    Keys.onSpacePressed: if (enabledAction) root.actionRequested(action)
    focus: true
  }

  Column {
    id: dashboard

    width: root.implicitWidth
    spacing: root.gridGap

    GlassTile {
      id: statusTile
      title: "VPN STATUS / ACTIVE CONNECTION"
      width: parent.width
      tileHeight: 222

      Rectangle { x: 25; y: 54; width: 10; height: 10; radius: 5; color: Ui.color(root.connectionState) }
      Text { x: 43; y: 49; text: Ui.label(root.connectionState).toUpperCase(); color: Ui.color(root.connectionState); font.family: "Noto Sans"; font.pixelSize: 13; font.bold: true; font.letterSpacing: .08 }
      Text { x: 25; y: 83; text: (root.server.flag || "◈") + "  " + (root.server.city || root.server.name || "VPN connection"); color: "#F7FFFFFF"; font.family: "Noto Sans"; font.pixelSize: 28; font.bold: true; elide: Text.ElideRight; width: parent.width - 50 }
      Text { x: 25; y: 121; text: (root.client.name || "VPN client") + (root.server.name ? " · " + root.server.name : "") + " · " + Ui.label(root.connectionState); color: "#D6E8F0"; font.family: "Noto Sans"; font.pixelSize: 13; width: parent.width - 50; elide: Text.ElideRight }
      Text { x: 25; y: 154; text: root.server.exitIp ? "External IP · " + root.server.exitIp : "External IP · Unknown"; color: "#BFD3DE"; font.family: "Noto Sans"; font.pixelSize: 12 }
      GlassButton { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.rightMargin: 24; anchors.bottomMargin: 22; text: root.primaryAction.text; action: root.primaryAction.action; enabledAction: root.primaryAction.enabled; kind: root.primaryAction.kind }
    }

    Flow {
      id: metricsRow
      width: parent.width
      spacing: root.gridGap
      height: root.gridColumns === 1 ? latencyTile.height + root.gridGap + networkTile.height : latencyTile.height

      GlassTile {
        id: latencyTile
        title: "LATENCY"
        width: root.gridTileWidth
        Text { x: 24; y: 53; text: root.latencyText; color: "#F7FFFFFF"; font.family: "Noto Sans"; font.pixelSize: 33; font.bold: true }
        Text { x: 24; y: 99; text: root.pingValue === undefined || root.pingValue === null ? "Not tested" : Ui.latencyLabel(root.pingValue) + " · " + (root.diagnostics.packetLoss === undefined || root.diagnostics.packetLoss === null ? "loss unknown" : root.diagnostics.packetLoss + "% loss"); color: "#C4D9E4"; font.family: "Noto Sans"; font.pixelSize: 12 }
      }

      GlassTile {
        id: networkTile
        title: "NETWORK"
        width: root.gridTileWidth
        Text { x: 24; y: 53; text: root.networkText; color: "#F7FFFFFF"; font.family: "Noto Sans"; font.pixelSize: root.networkText === "— / —" ? 25 : 21; font.bold: true }
        Text { x: 24; y: 101; text: root.traffic.inputBytes === undefined || root.traffic.outputBytes === undefined ? "Input / Output unavailable" : "Input " + Ui.formatBytes(root.traffic.inputBytes) + " · Output " + Ui.formatBytes(root.traffic.outputBytes); color: "#C4D9E4"; font.family: "Noto Sans"; font.pixelSize: 11; width: parent.width - 48; elide: Text.ElideRight }
      }
    }

    Flow {
      id: clientInterfaceRow
      width: parent.width
      spacing: root.gridGap
      height: root.gridColumns === 1 ? clientTile.height + root.gridGap + interfaceTile.height : clientTile.height

      GlassTile {
        id: clientTile
        title: "VPN CLIENT"
        width: root.gridTileWidth
        Text { x: 24; y: 51; text: root.client.name || "Not detected"; color: "#F7FFFFFF"; font.family: "Noto Sans"; font.pixelSize: 20; font.bold: true; width: parent.width - 48; elide: Text.ElideRight }
        Text { x: 24; y: 82; text: root.client.state || "UNKNOWN"; color: "#C4D9E4"; font.family: "Noto Sans"; font.pixelSize: 12 }
        Row {
          x: 24
          y: 100
          spacing: 7
          GlassButton { text: "Start"; action: "start"; enabledAction: !!root.capabilities.start; kind: "secondary"; implicitHeight: 31 }
          GlassButton { text: "Stop"; action: "stop"; enabledAction: !!root.capabilities.stop; kind: "secondary"; implicitHeight: 31 }
        }
      }

      GlassTile {
        id: interfaceTile
        title: "VPN INTERFACE"
        width: root.gridTileWidth
        Text { x: 24; y: 51; text: root.iface.name || "Not detected"; color: "#F7FFFFFF"; font.family: "Noto Sans"; font.pixelSize: 20; font.bold: true; width: parent.width - 48; elide: Text.ElideRight }
        Text { x: 24; y: 82; text: root.iface.name ? (root.iface.state || "UNKNOWN") + (root.iface.ip ? " · " + root.iface.ip : "") : "Managed by VPN client"; color: "#C4D9E4"; font.family: "Noto Sans"; font.pixelSize: 12; width: parent.width - 48; elide: Text.ElideRight }
        Text { x: 24; y: 107; visible: !root.capabilities.toggleInterface; text: "Managed by VPN client"; color: "#91A9B5"; font.family: "Noto Sans"; font.pixelSize: 11 }
      }
    }

    GlassTile {
      id: detailsTile
      title: "CONNECTION DETAILS"
      width: parent.width
      tileHeight: 126

      Row {
        id: detailsRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        spacing: 16

        Column {
          width: (detailsRow.width - detailsRow.spacing * 3) / 4
          spacing: 4
          Text { text: "Server"; color: "#AFC3CE"; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
          Text { text: root.server.name || "Unknown"; color: "#F7FFFFFF"; font.pixelSize: 14; font.bold: true; width: parent.width; elide: Text.ElideRight }
        }
        Column {
          width: (detailsRow.width - detailsRow.spacing * 3) / 4
          spacing: 4
          Text { text: "Region"; color: "#AFC3CE"; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
          Text { text: root.server.city || "Unknown"; color: "#F7FFFFFF"; font.pixelSize: 14; font.bold: true; width: parent.width; elide: Text.ElideRight }
        }
        Column {
          width: (detailsRow.width - detailsRow.spacing * 3) / 4
          spacing: 4
          Text { text: "Country"; color: "#AFC3CE"; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
          Text { text: root.server.country || "Unknown"; color: "#F7FFFFFF"; font.pixelSize: 14; font.bold: true; width: parent.width; elide: Text.ElideRight }
        }
        Column {
          width: (detailsRow.width - detailsRow.spacing * 3) / 4
          spacing: 4
          Text { text: "Protocol"; color: "#AFC3CE"; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
          Text { text: root.iface.type || "Unknown"; color: "#F7FFFFFF"; font.pixelSize: 14; font.bold: true; width: parent.width; elide: Text.ElideRight }
        }
      }
    }

    GlassTile {
      id: diagnosticsTile
      title: "DIAGNOSTICS"
      width: parent.width
      tileHeight: 162

      Text { x: 24; y: 52; text: "Ping  " + root.latencyText + "     DNS  " + (root.diagnostics.dns && root.diagnostics.dns.success ? "Success" : "Not tested") + "     HTTP  " + (root.diagnostics.http && root.diagnostics.http.success ? "Success" : "Not tested"); color: "#DDEBF1"; font.family: "Noto Sans"; font.pixelSize: 13; width: parent.width - 48; elide: Text.ElideRight }
      Row {
        x: 24
        y: 95
        spacing: 8
        GlassButton { text: "Check connection"; action: "diagnostics"; enabledAction: !!root.capabilities.ping; kind: "secondary" }
        GlassButton { text: "Speed test"; action: "speed-test"; enabledAction: !!root.capabilities.speedTest; kind: "secondary" }
      }
    }
  }
}
