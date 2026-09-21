import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "notifications.local"
  property int unread: 0
  property bool opened: false
  readonly property color bellColor: unread > 0 ? Color.urgent : (bar ? bar.foreground : Color.foreground)

  function refresh() { unreadProc.running = true }
  function openHistory() {
    historyProc.running = true
    root.unread = 0
  }

  Process {
    id: unreadProc
    command: ["omarchy-shell", "notifications", "unreadCount"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.unread = Math.max(0, Number(String(text || "0").trim()) || 0)
    }
  }
  Process {
    id: historyProc
    command: ["omarchy-shell", "notifications", "showHistory"]
  }
  Timer {
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    anchors.fill: parent
    bar: root.bar
    text: unread > 0 ? "🔔 " + unread : "🔔"
    tooltipText: unread > 0 ? unread + " unread notifications" : "No unread notifications"
    onPressed: function(button) {
      if (button === Qt.LeftButton) root.openHistory()
      else if (button === Qt.RightButton) root.unread = 0
    }
  }
}
