import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "health"
  readonly property string healthBackend: Quickshell.env("HOME") + "/.config/omarchy/plugins/health/metrics-backend"

  property var report: null
  readonly property bool ready: report !== null
  readonly property int cpu: ready ? Number(report.cpu || 0) : 0
  readonly property int memory: ready ? Number(report.memory || 0) : 0
  readonly property int disk: ready ? Number(report.disk || 0) : 0
  readonly property int temperature: ready ? Number(report.temperature || 0) : 0
  readonly property string uptime: ready ? String(report.uptime || "—") : "—"
  property bool opened: false
  readonly property bool popoutSwitchClosing: false

  function refresh() {
    if (!backend.running) backend.running = true
  }

  function toggle() { opened = !opened }
  function open() { opened = true }
  function close() { opened = false }

  Process {
    id: backend
    command: [root.healthBackend]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var value = JSON.parse(text || "{}")
          if (isFinite(Number(value.cpu)) && isFinite(Number(value.memory))) root.report = value
        } catch (error) {
          console.warn("health: backend response rejected: " + error)
        }
      }
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.ready ? "♨ " + root.temperature + "° " + root.memory + "%" : ""
    slotSize: Style.bar.statusSlot * 2
    tooltipText: root.ready
      ? "CPU " + root.cpu + "% · RAM " + root.memory + "% · диск " + root.disk + "%"
      : "System health"
    onPressed: function(b) {
      if (b === Qt.LeftButton || b === Qt.RightButton) root.toggle()
    }
  }

  PopupCard {
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
      spacing: Style.space(10)

      Text {
        text: "System health"
        color: "#cacccc"
        font.family: "sans-serif"
        font.pixelSize: 14
        font.bold: true
      }

      Text {
        text: "Обновляется каждые 5 секунд · только чтение"
        color: "#707880"
        font.pixelSize: 11
      }

      Repeater {
        model: [
          {name: "CPU", value: root.cpu + "%"},
          {name: "RAM", value: root.memory + "%"},
          {name: "Диск /", value: root.disk + "%"},
          {name: "Температура", value: root.temperature > 0 ? root.temperature + "°C" : "нет датчика"},
          {name: "Uptime", value: root.uptime}
        ]
        delegate: Row {
          required property var modelData
          width: 280
          spacing: Style.space(10)
          Text { text: modelData.name; color: "#707880"; font.pixelSize: 12; width: 120 }
          Text { text: modelData.value; color: "#cacccc"; font.pixelSize: 12; font.bold: true }
        }
      }
    }
  }
}
