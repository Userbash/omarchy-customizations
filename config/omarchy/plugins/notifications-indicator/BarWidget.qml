import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "notifications-indicator"
  width: 32
  height: 26
  implicitWidth: 32
  implicitHeight: 26

  property int unread: 0
  property bool opened: false
  readonly property string notificationDir: Quickshell.env("HOME") + "/.local/state/omarchy/notifications"
  readonly property string readMarker: Quickshell.env("HOME") + "/.local/state/omarchy/notifications-read"
  ListModel { id: missedModel }

  function openHistory() {
    root.opened = true
    root.unread = 0
    missedModel.clear()
    historyReadProc.running = true
    markReadProc.running = true
  }
  function runIpc(method) {
    actionProc.command = ["omarchy-shell", "notifications", method]
    actionProc.running = true
  }

  Process {
    id: unreadProc
    command: ["bash", "-c", "m=$(cat -- \"$2\" 2>/dev/null || printf 0); find -- \"$1\" -maxdepth 2 -type f -name '*.json' -printf '%f\\n' 2>/dev/null | awk -F- -v m=\"$m\" '$1 > m {n++} END {print n+0}'", "--", root.notificationDir, root.readMarker]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.unread = Math.max(0, Number(String(text || "0").trim()) || 0)
    }
  }
  Process {
    id: historyReadProc
    command: ["bash", "-c", "for f in \"$1\"/*.json \"$1\"/history/*.json; do [ -f \"$f\" ] || continue; cat -- \"$f\"; printf '\\n'; done", "--", root.notificationDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split(/\r?\n/)
        for (var i = lines.length - 1; i >= 0; --i) {
          var line = lines[i].trim()
          if (!line) continue
          try {
            var row = JSON.parse(line)
            missedModel.append({summary: String(row.summary || "Уведомление"), body: String(row.body || "")})
          } catch (e) { console.warn("notifications-indicator: invalid history row") }
        }
      }
    }
  }
  Process { id: actionProc; command: ["true"] }
  Process { id: markReadProc; command: ["bash", "-c", "mkdir -p -- \"$1\"; date +%s%3N > \"$2\"", "--", Quickshell.env("HOME") + "/.local/state/omarchy", root.readMarker] }
  Timer { interval: 1500; repeat: true; running: true; triggeredOnStart: true; onTriggered: if (!unreadProc.running) unreadProc.running = true }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "🔔"
    slotSize: 28
    fixedWidth: 28
    active: root.unread > 0
    activeColor: Color.urgent
    tooltipText: root.unread > 0 ? "Непрочитанных: " + root.unread : "Уведомления"
    onPressed: function(buttonId) {
      if (buttonId === Qt.LeftButton) root.openHistory()
      else if (buttonId === Qt.RightButton) root.runIpc("dismissAll")
    }
  }
  Rectangle {
    visible: root.unread > 0
    z: 10
    width: Math.max(16, badgeText.implicitWidth + 6)
    height: 16
    radius: 8
    anchors.right: button.right
    anchors.top: button.top
    color: Color.urgent
    Text { id: badgeText; anchors.centerIn: parent; text: root.unread > 99 ? "99+" : String(root.unread); color: Color.background; font.pixelSize: Style.font.caption; font.bold: true }
  }
  PopupCard {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: fittedContentWidth(Style.space(340))
    contentHeight: fittedContentHeight(menu.implicitHeight)
    Column {
      id: menu
      anchors.fill: parent
      spacing: Style.space(8)
      Text { text: "Уведомления"; color: root.bar ? root.bar.foreground : Color.foreground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.subtitle; font.bold: true }
      Text { text: missedModel.count > 0 ? "Пропущенных: " + missedModel.count : "Нет пропущенных уведомлений"; color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.35); font.pixelSize: Style.font.bodySmall }
      ListView {
        id: missedList
        width: parent.width
        height: Math.min(Style.space(300), Math.max(Style.space(48), contentHeight))
        visible: count > 0
        clip: true
        spacing: Style.space(6)
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {
          policy: ScrollBar.AsNeeded
          active: missedList.moving || missedList.contentHeight > missedList.height
        }
        model: missedModel
        delegate: Column {
          required property string summary
          required property string body
          width: missedList.width
          spacing: Style.space(2)
          Text { text: summary; color: root.bar ? root.bar.foreground : Color.foreground; font.pixelSize: Style.font.bodySmall; font.bold: true; elide: Text.ElideRight; width: parent.width }
          Text { text: body; color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.35); font.pixelSize: Style.font.caption; maximumLineCount: 2; wrapMode: Text.WordWrap; elide: Text.ElideRight; width: parent.width }
        }
      }
      Row {
        spacing: Style.space(8)
        PanelActionButton { iconText: "󰆴"; tooltipText: "Очистить историю"; hoverColor: Color.urgent; onClicked: { root.runIpc("clear"); missedModel.clear(); root.unread = 0; root.opened = false } }
        PanelActionButton { iconText: "󰂛"; tooltipText: "Закрыть всплывающие"; onClicked: { root.runIpc("dismissAll"); root.opened = false } }
      }
    }
  }
}
