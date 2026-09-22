import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons

PopupWindow {
  id: root

  required property Item anchorItem
  required property var bar
  property var owner: null
  property bool open: false
  property int margin: Style.gapsOut
  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
  readonly property real screenW: popupScreen ? popupScreen.width : 0
  readonly property real screenH: popupScreen ? popupScreen.height : 0

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  default property alias contentChildren: contentHolder.children

  visible: open || surface.opacity > 0
  color: "transparent"
  implicitWidth: Style.space(344)
  implicitHeight: Style.space(210)

  onOpenChanged: {
    if (!bar) return
    if (open && typeof bar.requestPopout === "function") bar.requestPopout(coordinatorKey)
    else if (!open && bar.activePopout === coordinatorKey && typeof bar.releasePopout === "function") bar.releasePopout(coordinatorKey)
  }

  HyprlandFocusGrab {
    active: root.open
    windows: root.anchorWindow ? [root, root.anchorWindow] : [root]
    onCleared: root.close()
  }

  anchor {
    window: root.anchorWindow
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!root.anchorItem || !root.bar || !root.anchorWindow) return

      var popupWidth = root.implicitWidth
      var popupHeight = root.implicitHeight
      var localX = root.anchorItem.width / 2 - popupWidth / 2
      var localY = root.anchorItem.height + root.margin

      if (root.bar.position === "bottom") localY = -popupHeight - root.margin
      else if (root.bar.position === "left") {
        localX = root.anchorItem.width + root.margin
        localY = root.anchorItem.height / 2 - popupHeight / 2
      } else if (root.bar.position === "right") {
        localX = -popupWidth - root.margin
        localY = root.anchorItem.height / 2 - popupHeight / 2
      }

      var point = root.anchorWindow.contentItem.mapFromItem(root.anchorItem, localX, localY)
      if (root.bar.position === "top" || root.bar.position === "bottom") {
        point.x = Math.max(root.margin, Math.min(point.x, root.anchorWindow.width - popupWidth - root.margin))
      } else {
        point.y = Math.max(root.margin, Math.min(point.y, root.anchorWindow.height - popupHeight - root.margin))
      }
      root.anchor.rect.x = Math.round(point.x)
      root.anchor.rect.y = Math.round(point.y)
    }
  }

  Rectangle {
    id: surface
    anchors.fill: parent
    radius: Math.max(10, Style.cornerRadius)
    color: "#FF222A33"
    border.width: 1
    border.color: "#59FFFFFF"
    opacity: root.open ? 1 : 0
    clip: true

    Behavior on opacity {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: parent.height * .32
      radius: parent.radius
      color: "#182E3944"
    }

    Item {
      id: contentHolder
      anchors.fill: parent
    }
  }
}
