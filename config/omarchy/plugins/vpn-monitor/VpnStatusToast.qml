import QtQuick
import "VpnUiModel.js" as Ui

Item {
  id: root

  property var status: ({})
  property bool diagnosticInProgress: false
  property bool operationInProgress: false
  property string operationAction: ""
  property string errorMessage: ""
  property double lastConnectionClickMs: -1000
  signal actionRequested(string action)

  readonly property var client: status && status.client ? status.client : ({})
  readonly property var connection: status && status.connection ? status.connection : ({})
  readonly property var iface: status && status.interface ? status.interface : ({})
  readonly property var server: status && status.server ? status.server : ({})
  readonly property var diagnostics: status && status.diagnostics ? status.diagnostics : ({})
  readonly property var traffic: status && status.traffic ? status.traffic : ({})
  readonly property var capabilities: status && status.capabilities ? status.capabilities : ({})
  readonly property var speedTest: diagnostics.speedTest || ({})
  readonly property string connectionState: String(connection.state || "UNKNOWN")
  readonly property string connectionText: Ui.label(connectionState)
  readonly property string clientText: client.name || "VPN"
  readonly property bool diagnosticsBusy: diagnosticInProgress || operationAction === "diagnostics"
  readonly property bool speedBusy: operationAction === "speed-test" || operationAction === "speed-test-cancel"
  readonly property string locationText: server.flag && server.country
    ? server.flag + " " + server.country
    : (server.country || (connectionState === "CONNECTED" || connectionState === "DEGRADED" ? "VPN-выход определяется…" : "VPN не подключен"))
  readonly property string exitIpText: server.exitIp ? "Выход " + server.exitIp : "Внешний IP не определен"
  readonly property string warpText: server.usesWarp === true ? "WARP: включен"
    : (server.usesWarp === false ? "WARP: нет" : "WARP: неизвестно")
  readonly property string interfaceText: iface.name
    ? iface.name + " · " + String(iface.state || "UNKNOWN") + (iface.ip ? " · " + iface.ip : "")
    : "TUN/TAP не найден"
  readonly property string latencyText: diagnostics.pingMs === undefined || diagnostics.pingMs === null
    ? "Не проверено"
    : Math.max(1, Math.round(Number(diagnostics.pingMs))) + " мс · " + (diagnostics.ping && diagnostics.ping.viaVpn === true || diagnostics.http && diagnostics.http.viaVpn === true ? "через VPN" : "потери " + (diagnostics.packetLoss === undefined || diagnostics.packetLoss === null ? "—" : diagnostics.packetLoss + "%"))
  readonly property int httpPassed: Number(diagnostics.http && diagnostics.http.passed !== undefined ? diagnostics.http.passed : 0)
  readonly property int httpTotal: Number(diagnostics.http && diagnostics.http.total !== undefined ? diagnostics.http.total : 0)
  readonly property string httpText: httpTotal > 0
    ? "HTTP " + httpPassed + "/" + httpTotal + (diagnostics.http.viaVpn === true ? " · VPN" : "")
    : "HTTP не проверен"
  readonly property string throughputText: traffic.downloadMbps === undefined || traffic.downloadMbps === null
      || traffic.uploadMbps === undefined || traffic.uploadMbps === null
    ? "↓ —  ↑ — Мбит/с"
    : "↓ " + Number(traffic.downloadMbps).toFixed(2) + "  ↑ " + Number(traffic.uploadMbps).toFixed(2) + " Мбит/с"
  readonly property string trafficText: traffic.inputBytes === undefined || traffic.inputBytes === null
      || traffic.outputBytes === undefined || traffic.outputBytes === null
    ? "Вход — · Выход —"
    : "Вход " + Ui.formatBytes(traffic.inputBytes) + " · Выход " + Ui.formatBytes(traffic.outputBytes)
  readonly property bool canCheck: !!capabilities.ping && !diagnosticsBusy
  readonly property string speedTestState: String(speedTest.status || "IDLE")
  readonly property bool speedTestRunning: speedTestState === "STARTED" || speedTestState === "RUNNING" || speedTestState === "CANCELLING"
  readonly property bool canSpeedTest: !!capabilities.speedTest && connectionState === "CONNECTED" && !speedBusy && !speedTestRunning
  readonly property bool canCancelSpeedTest: !!speedTest.testId && speedTestRunning && operationAction !== "diagnostics"
  readonly property string speedDisplayText: speedTestState === "COMPLETED"
    ? "Тест ↓ " + Number(speedTest.downloadMbps).toFixed(2) + "  ↑ " + Number(speedTest.uploadMbps).toFixed(2) + " Мбит/с"
    : (speedTestRunning ? "Тест скорости…" : (speedTestState === "ERROR" ? "Тест скорости: ошибка" : root.throughputText))
  readonly property string connectionAction: !operationInProgress && connectionState === "CONNECTED" && capabilities.disconnect
    ? "disconnect" : (!operationInProgress && connectionState === "DISCONNECTED" && capabilities.connect ? "connect" : "")
  readonly property string clientAction: connectionAction !== "" ? connectionAction
    : (!operationInProgress && client.state === "RUNNING" && capabilities.stop ? "stop"
      : (!operationInProgress && client.state === "INSTALLED_STOPPED" && capabilities.start ? "start" : ""))
  readonly property string clientActionText: clientAction === "connect" ? "Подключить"
    : (clientAction === "disconnect" ? "Отключить" : (clientAction === "start" ? "Запустить" : "Остановить"))
  readonly property string checkText: diagnosticInProgress ? "Проверка…" : "Проверить"

  objectName: "vpnStatusToast"
  implicitWidth: 344
  implicitHeight: 210

  component ToastActionButton: Rectangle {
    id: actionButton
    property string action: ""
    property string label: ""
    property bool actionEnabled: false
    signal requested(string action)
    implicitWidth: actionLabel.implicitWidth + 22
    implicitHeight: 28
    radius: 8
    color: actionArea.pressed && actionEnabled ? "#4DFFFFFF" : "#2BFFFFFF"
    border.width: 1
    border.color: "#47FFFFFF"
    opacity: actionEnabled ? 1 : .46

    Text {
      id: actionLabel
      anchors.centerIn: parent
      text: actionButton.label
      color: "#F2F7FA"
      font.family: "Noto Sans"
      font.pixelSize: 11
      font.bold: true
    }

    MouseArea {
      id: actionArea
      objectName: actionButton.action === "diagnostics" ? "vpnToastCheckArea" : "vpnToastActionArea_" + actionButton.action
      anchors.fill: parent
      enabled: actionButton.actionEnabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: actionButton.requested(actionButton.action)
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: 38
    radius: 10
    color: "#20FFFFFF"
  }

  MouseArea {
    id: connectionArea
    objectName: "vpnToastConnectionArea"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: 38
    enabled: root.connectionAction !== ""
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: {
      var now = Date.now()
      if (now - root.lastConnectionClickMs <= 400) {
        root.lastConnectionClickMs = -1000
        root.actionRequested(root.connectionAction)
      } else {
        root.lastConnectionClickMs = now
      }
    }
  }

  Rectangle {
    x: 14
    y: 14
    width: 8
    height: 8
    radius: 4
    color: Ui.color(root.connectionState)
  }

  Text {
    x: 29
    y: 9
    text: root.connectionText
    color: Ui.color(root.connectionState)
    font.family: "Noto Sans"
    font.pixelSize: 12
    font.bold: true
  }

  Text {
    anchors.right: parent.right
    anchors.rightMargin: 14
    y: 9
    width: 150
    horizontalAlignment: Text.AlignRight
    text: root.clientText
    color: "#F2F7FA"
    font.family: "Noto Sans"
    font.pixelSize: 12
    font.bold: true
    elide: Text.ElideRight
  }

  Text {
    x: 14
    y: 48
    width: parent.width - 28
    text: root.locationText
    color: "#F4F8FA"
    font.family: "Noto Sans"
    font.pixelSize: 17
    font.bold: true
    elide: Text.ElideRight
  }

  Text {
    x: 14
    y: 75
    width: 210
    text: root.exitIpText
    color: "#B8CBD5"
    font.family: "Noto Sans"
    font.pixelSize: 11
    elide: Text.ElideRight
  }

  Text {
    anchors.right: parent.right
    anchors.rightMargin: 14
    y: 75
    width: 105
    horizontalAlignment: Text.AlignRight
    text: root.warpText
    color: root.server.usesWarp === true ? "#92D7F4" : "#9DB5C1"
    font.family: "Noto Sans"
    font.pixelSize: 10
    elide: Text.ElideRight
  }

  Rectangle {
    x: 14
    y: 98
    width: parent.width - 28
    height: 1
    color: "#2EFFFFFF"
  }

  Text {
    x: 14
    y: 110
    text: "VPN HTTP"
    color: "#9DB5C1"
    font.family: "Noto Sans"
    font.pixelSize: 10
  }

  Text {
    anchors.right: parent.right
    anchors.rightMargin: 14
    y: 110
    width: 220
    horizontalAlignment: Text.AlignRight
    text: root.httpText + " · " + root.latencyText
    color: "#E6F0F5"
    font.family: "Noto Sans"
    font.pixelSize: 11
    elide: Text.ElideRight
  }

  Text {
    x: 14
    y: 132
    width: parent.width - 28
    text: root.speedDisplayText
    color: "#E6F0F5"
    font.family: "Noto Sans"
    font.pixelSize: 12
    font.bold: true
    elide: Text.ElideRight
  }

  Text {
    x: 14
    y: 153
    width: parent.width - 28
    text: root.errorMessage !== "" ? root.errorMessage : root.trafficText
    color: root.errorMessage !== "" ? "#FFB1B1" : "#AFC5D0"
    font.family: "Noto Sans"
    font.pixelSize: 10
    elide: Text.ElideRight
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: 14
    anchors.right: actionRow.left
    anchors.rightMargin: 10
    y: 184
    text: root.interfaceText
    color: "#9DB5C1"
    font.family: "Noto Sans"
    font.pixelSize: 10
    elide: Text.ElideRight
  }

  Row {
    id: actionRow
    anchors.right: parent.right
    anchors.rightMargin: 14
    y: 176
    spacing: 6

    ToastActionButton {
      action: "diagnostics"
      label: root.checkText
      actionEnabled: root.canCheck
      onRequested: function(action) { root.actionRequested(action) }
    }

    ToastActionButton {
      visible: root.capabilities.speedTest === true
      action: root.speedTestRunning ? "speed-test-cancel" : "speed-test"
      label: root.speedTestRunning ? "Отменить" : "Скорость"
      actionEnabled: root.speedTestRunning ? root.canCancelSpeedTest : root.canSpeedTest
      onRequested: function(action) { root.actionRequested(action) }
    }

    ToastActionButton {
      visible: root.clientAction !== ""
      action: root.clientAction
      label: root.clientActionText
      actionEnabled: root.clientAction !== ""
      onRequested: function(action) { root.actionRequested(action) }
    }
  }
}
