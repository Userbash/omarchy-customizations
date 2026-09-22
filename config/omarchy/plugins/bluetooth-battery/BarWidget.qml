import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui as ShellUi

ShellUi.BarWidget {
  id: root
  moduleName: "bluetooth-battery"
  property bool opened: false
  property alias backendClient: client
  readonly property var devices: client.devices || []
  readonly property var visibleDevices: devices.slice(0, 4)
  readonly property bool hasDevices: devices.length > 0
  readonly property string iconText: !client.adapterPowered ? "󰂲" : (hasDevices ? "󰂯" : "󰂯—")
  readonly property string compactText: {
    if (!hasDevices) return ""
    var known = devices.filter(function(item) { return item.batteryKnown })
    if (!known.length) return iconText + " ?"
    var minimum = Math.min.apply(null, known.map(function(item) { return Number(item.batteryPercent) }))
    return iconText + " " + minimum + "%"
  }
  // Reserve a real gap and separator so the percentage cannot visually merge
  // with the adjacent VPN widget in the right side of the bar.
  readonly property real interWidgetGap: Style.space(8)
  readonly property real separatorWidth: 1
  implicitWidth: hasDevices ? button.implicitWidth + interWidgetGap + separatorWidth : 0
  implicitHeight: button.implicitHeight

  function toggle() { root.opened = !root.opened }
  function open() { root.opened = true }
  function close() { root.opened = false }
  function deviceIcon(device) {
    return ({mouse: "🖱", keyboard: "⌨", headphones: "🎧", headset: "🎧", gamepad: "🎮", phone: "📱"})[device.type] || "󰂯"
  }
  function batteryText(device) {
    if (!device.batteryKnown || device.batteryPercent === null) return "—"
    return (device.charging ? "⚡ " : "") + device.batteryPercent + "%"
  }
  function batteryColor(device) {
    if (!device.batteryKnown) return "#9AA7AF"
    if (device.charging) return "#9FD6FF"
    if (Number(device.batteryPercent) <= 10) return "#FF6B6B"
    if (Number(device.batteryPercent) <= 20) return "#FFB347"
    if (Number(device.batteryPercent) <= 50) return "#FFD166"
    return "#7BE495"
  }
  function panelColor() {
    if (!hasDevices) return "#9AA7AF"
    var known = devices.filter(function(item) { return item.batteryKnown })
    if (!known.length) return "#9AA7AF"
    if (known.some(function(item) { return item.charging })) return "#9FD6FF"
    var minimum = Math.min.apply(null, known.map(function(item) { return Number(item.batteryPercent) }))
    return batteryColor({batteryKnown: true, batteryPercent: minimum, charging: false})
  }

  BluetoothBatteryClient { id: client }

  IpcHandler {
    target: "bluetooth-battery"
    function state(): string {
      return JSON.stringify({opened: root.opened, adapterPowered: client.adapterPowered, deviceCount: root.devices.length, compactText: root.compactText, panelColor: root.panelColor()})
    }
    function open(): void { root.open() }
    function close(): void { root.close() }
  }

  ShellUi.BarIconButton {
    id: button
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    bar: root.bar
    fixedWidth: -1
    text: root.compactText
    foreground: root.panelColor()
    activeColor: root.panelColor()
    tooltipText: client.lastError !== "" ? client.lastError : (hasDevices ? "Bluetooth: " + devices.length + " подключено" : "Bluetooth: нет подключённых устройств")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton || buttonCode === Qt.RightButton) root.toggle()
    }
  }

  Rectangle {
    id: separator
    visible: root.hasDevices
    x: button.implicitWidth + root.interWidgetGap / 2
    anchors.verticalCenter: button.verticalCenter
    width: root.separatorWidth
    height: Math.max(14, Math.round(button.height * 0.45))
    radius: width / 2
    color: Qt.rgba(0.60, 0.67, 0.70, 0.42)
  }

  ShellUi.PopupCard {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: fittedContentWidth(Style.space(330))
    contentHeight: fittedContentHeight(details.implicitHeight)

    Column {
      id: details
      anchors.fill: parent
      spacing: Style.space(8)
      Text { text: "Bluetooth"; color: "#F2F7FA"; font.pixelSize: 15; font.bold: true }
      Text {
        text: !client.adapterPowered ? "Bluetooth выключен" : (hasDevices ? "Подключённые устройства" : "Нет подключённых устройств")
        color: "#9DB5C1"; font.pixelSize: 11
      }
      Repeater {
        model: root.visibleDevices
        delegate: Row {
          required property var modelData
          width: details.width
          spacing: 8
          Text { text: root.deviceIcon(modelData); width: 25; font.pixelSize: 18 }
          Column {
            width: parent.width - 80
            Text { text: modelData.alias || modelData.name || modelData.address; color: "#F2F7FA"; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width }
            Text { text: modelData.connected ? (modelData.batteryKnown ? "Подключено · Заряд" : "Подключено · Заряд недоступен") : "Отключено"; color: "#9DB5C1"; font.pixelSize: 10 }
          }
          Text { text: root.batteryText(modelData); color: root.batteryColor(modelData); font.pixelSize: 12; font.bold: true }
        }
      }
      Text { visible: root.devices.length > 4; text: "+" + (root.devices.length - 4) + " устройств"; color: "#9DB5C1"; font.pixelSize: 10 }
    }
  }
}
