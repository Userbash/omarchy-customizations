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
  property int storedNotifications: 0
  property bool opened: false
  property bool doNotDisturb: false
  property double lastLeftClickMs: 0
  readonly property string notificationDir: Quickshell.env("HOME") + "/.local/state/omarchy/notifications"
  readonly property string readMarker: Quickshell.env("HOME") + "/.local/state/omarchy/notifications-read"

  ListModel { id: unreadModel }

  function refreshUnread() {
    if (!unreadProc.running) unreadProc.running = true
    if (!historyCountProc.running) historyCountProc.running = true
  }

  function refreshDnd() {
    if (!dndStateProc.running) dndStateProc.running = true
  }

  function openUnreadMenu() {
    unreadModel.clear()
    root.opened = true
    if (!historyReadProc.running) historyReadProc.running = true
  }

  function close() {
    root.opened = false
  }

  function markAllRead() {
    markReadProc.running = true
    root.unread = 0
    unreadModel.clear()
  }

  function clearHistory() {
    clearProc.running = true
    root.markAllRead()
  }

  function toggleDnd() {
    dndToggleProc.running = true
  }

  function deleteNotification(index, path) {
    if (!path || deleteProc.running) return
    deleteProc.targetIndex = index
    deleteProc.command = ["bash", "-c",
      "case \"$2\" in \"$1\"/*.json|\"$1\"/history/*.json) rm -f -- \"$2\";; *) exit 2;; esac",
      "--", root.notificationDir, path]
    deleteProc.running = true
  }

  Process {
    id: unreadProc
    command: ["bash", "-c",
      "m=$(cat -- \"$2\" 2>/dev/null || printf 0); " +
      "find -- \"$1\" -maxdepth 2 -type f -name '*.json' -printf '%f\\n' 2>/dev/null | " +
      "awk -F- -v m=\"$m\" '$1 ~ /^[0-9]+$/ && $1 > m {n++} END {print n+0}'",
      "--", root.notificationDir, root.readMarker]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.unread = Math.max(0, Number(String(text || "0").trim()) || 0)
    }
  }

  Process {
    id: historyCountProc
    command: ["bash", "-c",
      "find -- \"$1\" -maxdepth 2 -type f -name '*.json' -printf . 2>/dev/null | wc -c",
      "--", root.notificationDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.storedNotifications = Math.max(0, Number(String(text || "0").trim()) || 0)
    }
  }

  Process {
    id: historyReadProc
    command: ["bash", "-c",
      "m=$(cat -- \"$2\" 2>/dev/null || printf 0); " +
      "for f in \"$1\"/*.json \"$1\"/history/*.json; do " +
      "[ -f \"$f\" ] || continue; n=${f##*/}; t=${n%%-*}; " +
      "case $t in (*[!0-9]*|'') continue;; esac; [ \"$t\" -gt \"$m\" ] || continue; " +
      "printf '%s\\t' \"$f\"; cat -- \"$f\"; printf '\\n'; done",
      "--", root.notificationDir, root.readMarker]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split(/\r?\n/)
        for (var i = lines.length - 1; i >= 0; --i) {
          var line = lines[i].trim()
          if (!line) continue
          try {
            var separator = line.indexOf("\t")
            if (separator < 1) continue
            var path = line.slice(0, separator)
            var row = JSON.parse(line.slice(separator + 1))
            unreadModel.append({
              summary: String(row.summary || "Notification"),
              body: String(row.body || ""),
              timestamp: Number(row.timestamp || 0),
              filePath: path
            })
          } catch (error) {
            console.warn("notifications-indicator: skipped invalid history entry")
          }
        }
      }
    }
  }

  Process {
    id: markReadProc
    command: ["bash", "-c", "mkdir -p -- \"$1\" && date +%s%3N > \"$2\"", "--",
      Quickshell.env("HOME") + "/.local/state/omarchy", root.readMarker]
  }

  Process {
    id: clearProc
    command: ["omarchy-shell", "notifications", "clear"]
    onExited: root.refreshUnread()
  }

  Process {
    id: deleteProc
    property int targetIndex: -1
    command: ["true"]
    onExited: function(exitCode) {
      if (exitCode === 0 && targetIndex >= 0 && targetIndex < unreadModel.count)
        unreadModel.remove(targetIndex)
      targetIndex = -1
      root.refreshUnread()
    }
  }

  Process {
    id: dndStateProc
    command: ["omarchy-shell", "notifications", "dndState"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.doNotDisturb = String(text || "").trim() === "on"
    }
  }

  Process {
    id: dndToggleProc
    command: ["omarchy-shell", "notifications", "toggleDnd"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.doNotDisturb = String(text || "").trim() === "on"
        root.refreshUnread()
      }
    }
  }

  Timer {
    id: singleClickTimer
    interval: 280
    repeat: false
    onTriggered: root.openUnreadMenu()
  }

  Timer {
    interval: 1500
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      root.refreshUnread()
      root.refreshDnd()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.doNotDisturb ? "󰂛" : "󰂚"
    slotSize: 28
    fixedWidth: 28
    active: root.unread > 0 || root.doNotDisturb
    activeColor: root.doNotDisturb ? Color.urgent : Color.accent
    tooltipText: root.doNotDisturb
      ? "Notifications are silenced · double-click to enable"
      : (root.unread > 0 ? root.unread + " unread notifications" : "Notifications · double-click to silence")
    onPressed: function(buttonId) {
      if (buttonId !== Qt.LeftButton) {
        root.close()
        return
      }
      var now = Date.now()
      if (singleClickTimer.running && now - root.lastLeftClickMs <= 350) {
        singleClickTimer.stop()
        root.lastLeftClickMs = 0
        root.toggleDnd()
      } else {
        root.lastLeftClickMs = now
        singleClickTimer.restart()
      }
    }
  }

  Rectangle {
    id: unreadBadge
    visible: root.unread > 0 && !root.doNotDisturb
    z: 10
    width: Math.max(16, badgeText.implicitWidth + 6)
    height: 16
    radius: height / 2
    anchors.right: button.right
    anchors.top: button.top
    anchors.rightMargin: -4
    anchors.topMargin: -3
    color: Color.urgent
    border.width: 1
    border.color: root.bar ? root.bar.background : Color.background

    Text {
      id: badgeText
      anchors.centerIn: parent
      text: root.unread > 99 ? "99+" : String(root.unread)
      color: Color.background
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: fittedContentWidth(Style.space(380))
    contentHeight: fittedContentHeight(menu.implicitHeight, Style.space(470))

    Column {
      id: menu
      anchors.fill: parent
      spacing: Style.space(8)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Column {
          width: parent.width - dndButton.width - Style.space(8)
          spacing: Style.space(2)
          Text {
            text: "Unread notifications"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            text: root.doNotDisturb
              ? "Do Not Disturb is on · " + root.storedNotifications + " saved"
              : unreadModel.count + " unread · " + root.storedNotifications + " saved"
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.35)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        PanelActionButton {
          id: dndButton
          iconText: root.doNotDisturb ? "󰂚" : "󰂛"
          tooltipText: root.doNotDisturb ? "Enable notifications" : "Silence notifications"
          hoverColor: root.doNotDisturb ? Color.accent : Color.urgent
          onClicked: root.toggleDnd()
        }
      }

      Text {
        visible: unreadModel.count === 0
        width: parent.width
        text: "No unread notifications"
        color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      ListView {
        id: unreadList
        width: parent.width
        height: Math.min(Style.space(300), Math.max(0, contentHeight))
        visible: count > 0
        clip: true
        spacing: Style.space(8)
        boundsBehavior: Flickable.StopAtBounds
        model: unreadModel

        ScrollBar.vertical: ScrollBar {
          policy: ScrollBar.AsNeeded
          active: unreadList.moving || unreadList.contentHeight > unreadList.height
        }

        delegate: Item {
          required property string summary
          required property string body
          required property string filePath
          width: unreadList.width - Style.space(8)
          implicitHeight: row.implicitHeight

          Row {
            id: row
            width: parent.width
            spacing: Style.space(6)

            Column {
              width: parent.width - deleteButton.width - parent.spacing
              spacing: Style.space(2)
              Text {
                text: summary
                width: parent.width
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                text: body
                width: parent.width
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.35)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }
            }

            PanelActionButton {
              id: deleteButton
              iconText: "󰆴"
              tooltipText: "Delete this notification"
              hoverColor: Color.urgent
              onClicked: root.deleteNotification(index, filePath)
            }
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        PanelActionButton {
          iconText: "󰄬"
          tooltipText: "Mark all as read"
          enabled: unreadModel.count > 0
          onClicked: root.markAllRead()
        }
        PanelActionButton {
          iconText: "󰆴"
          tooltipText: "Clear notification history"
          hoverColor: Color.urgent
          enabled: root.storedNotifications > 0
          onClicked: root.clearHistory()
        }
      }
    }
  }
}
