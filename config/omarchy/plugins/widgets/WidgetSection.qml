import QtQuick
import QtQuick.Layouts

Item {
  id: root

  property string sectionId: ""
  property string title: ""
  property var tileIds: []
  property var availableTiles: []
  property var dashboard: null
  property Item dragLayer: null
  property bool editing: false
  property bool catalogOpen: false
  property bool sectionDropTarget: false
  property bool sectionDropAfter: false
  property bool tileDropTarget: false
  property bool dragInProgress: false
  property point dragStartPosition: Qt.point(0, 0)
  property point dragHotSpot: Qt.point(0, 0)
  property point dragTranslation: Qt.point(0, 0)
  property var pendingDropTarget: null
  property bool pendingDropAfter: false
  readonly property string dragType: "section"
  readonly property bool containsDrag: sectionDrop.containsDrag

  function containsDragPoint(target, x, y) {
    if (!target || !root.dragLayer) return false
    var point = target.mapFromItem(root.dragLayer, x, y)
    return point.x >= 0 && point.y >= 0 && point.x <= target.width && point.y <= target.height
  }

  implicitWidth: 440
  implicitHeight: sectionLayout.implicitHeight
  z: dragInProgress ? 15 : 0
  scale: dragInProgress ? 1.02 : 1
  opacity: dragInProgress ? 0.9 : 1
  transform: Translate {
    x: root.dragInProgress ? root.dragTranslation.x : 0
    y: root.dragInProgress ? root.dragTranslation.y : 0
    Behavior on x {
      enabled: !root.dragInProgress
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
    Behavior on y {
      enabled: !root.dragInProgress
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
  }

  DropArea {
    id: sectionDrop
    anchors.fill: parent
    z: -1
    enabled: root.editing && !root.dashboard.widgetLayout.locked && !root.dragInProgress
    keys: ["omarchy-widget-tile", "omarchy-widget-section"]

    onEntered: function(drop) {
      if (!drop.source || drop.source === root) return
      if (drop.source.dragType === "section") {
        drop.acceptProposedAction()
        root.sectionDropTarget = true
        root.sectionDropAfter = drop.y >= root.height / 2
        drop.source.pendingDropTarget = root
        drop.source.pendingDropAfter = root.sectionDropAfter
      } else if (drop.source.dragType === "tile") {
        root.tileDropTarget = drop.source.sectionId !== root.sectionId
          && (drop.source.tileId !== "player" || root.sectionId === "media")
        if (root.tileDropTarget) {
          drop.acceptProposedAction()
          drop.source.pendingDropSectionTarget = root
        }
      }
    }

    onPositionChanged: function(drop) {
      if (!drop.source || drop.source === root) return
      if (drop.source.dragType === "section") {
        drop.acceptProposedAction()
        root.sectionDropTarget = true
        root.sectionDropAfter = drop.y >= root.height / 2
        drop.source.pendingDropTarget = root
        drop.source.pendingDropAfter = root.sectionDropAfter
      } else if (drop.source.dragType === "tile") {
        root.tileDropTarget = drop.source.sectionId !== root.sectionId
          && (drop.source.tileId !== "player" || root.sectionId === "media")
        if (root.tileDropTarget) {
          drop.acceptProposedAction()
          drop.source.pendingDropSectionTarget = root
        }
      }
    }

    onExited: {
      root.sectionDropTarget = false
      root.tileDropTarget = false
    }

    onDropped: function(drop) {
      if (!drop.source || drop.source === root) return
      if (drop.source.dragType === "section") {
        drop.accept(Qt.MoveAction)
        root.dashboard.moveSectionTo(drop.source.sectionId, root.sectionId, root.sectionDropAfter)
      } else if (drop.source.dragType === "tile"
          && drop.source.sectionId !== root.sectionId
          && (drop.source.tileId !== "player" || root.sectionId === "media")) {
        drop.accept(Qt.MoveAction)
        root.dashboard.moveTile(drop.source.tileId, root.sectionId, "", true)
      }
      root.sectionDropTarget = false
      root.tileDropTarget = false
    }
  }

  ColumnLayout {
    id: sectionLayout
    anchors.fill: parent
    spacing: 8

    RowLayout {
      Layout.fillWidth: true
      Layout.preferredHeight: 25
      spacing: 5

      Rectangle {
        id: dragHandle
        visible: root.editing
        Layout.preferredWidth: 23
        Layout.preferredHeight: 23
        radius: 8
        color: sectionDrag.active ? root.dashboard.accentSurface : root.dashboard.raisedSurface
        border.width: 1
        border.color: sectionDrag.active ? root.dashboard.accentColor : root.dashboard.surfaceBorder
        opacity: root.dashboard.widgetLayout.locked ? 0.45 : 1

        Text {
          anchors.centerIn: parent
          text: "⋮⋮"
          color: root.dashboard.secondaryText
          font.family: root.dashboard.uiFont
          font.pixelSize: 13
          font.bold: true
        }

        DragHandler {
          id: sectionDrag
          enabled: root.editing && !root.dashboard.widgetLayout.locked
          target: null
          acceptedButtons: Qt.LeftButton
          cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
          onActiveTranslationChanged: {
            if (active) root.dragTranslation = activeTranslation
          }
          onActiveChanged: {
            if (active) {
              if (!root.dragLayer) return
              root.dragStartPosition = root.mapToItem(root.dragLayer, 0, 0)
              root.dragTranslation = Qt.point(0, 0)
              root.dragHotSpot = Qt.point(
                dragHandle.x + sectionDrag.centroid.position.x,
                dragHandle.y + sectionDrag.centroid.position.y
              )
              root.pendingDropTarget = null
              root.pendingDropAfter = false
              root.dragInProgress = true
              root.dashboard.draggingItems = true
            } else if (root.dragInProgress) {
              var target = root.pendingDropTarget
              var targetSectionId = target ? target.sectionId : ""
              var targetAfter = root.pendingDropAfter
              var pointX = root.dragStartPosition.x + root.dragTranslation.x + root.dragHotSpot.x
              var pointY = root.dragStartPosition.y + root.dragTranslation.y + root.dragHotSpot.y
              var insideTarget = root.containsDragPoint(target, pointX, pointY)
              root.pendingDropTarget = null
              root.dragInProgress = false
              root.dashboard.draggingItems = false
              if (insideTarget && targetSectionId !== "" && targetSectionId !== root.sectionId) {
                root.dashboard.moveSectionTo(root.sectionId, targetSectionId, targetAfter)
              }
            }
          }
        }
      }

      Loader {
        Layout.fillWidth: true
        Layout.preferredHeight: 24
        sourceComponent: root.editing ? editSectionTitle : displaySectionTitle
      }

      Rectangle {
        width: 25
        height: 22
        radius: 11
        color: root.dashboard.raisedSurface
        border.width: 1
        border.color: root.dashboard.surfaceBorder

        Text {
          anchors.centerIn: parent
          text: root.tileIds.length
          color: root.dashboard.secondaryText
          font.family: root.dashboard.uiFont
          font.pixelSize: 10
          font.bold: true
        }
      }

      Repeater {
        model: root.editing ? [
          { label: "↑", name: "Переместить раздел выше", offset: -1 },
          { label: "↓", name: "Переместить раздел ниже", offset: 1 }
        ] : []

        delegate: Rectangle {
          required property var modelData
          property int indexInLayout: root.dashboard.sectionIndex(root.sectionId)
          width: 24
          height: 23
          radius: 8
          color: mouse.containsMouse ? root.dashboard.accentHover : root.dashboard.raisedSurface
          border.width: 1
          border.color: root.dashboard.surfaceBorder
          opacity: (modelData.offset < 0 && indexInLayout === 0)
            || (modelData.offset > 0 && indexInLayout === root.dashboard.widgetLayout.sections.length - 1)
            || root.dashboard.widgetLayout.locked ? 0.4 : 1

          Text {
            anchors.centerIn: parent
            text: modelData.label
            color: root.dashboard.primaryText
            font.family: root.dashboard.uiFont
            font.pixelSize: 13
            font.bold: true
          }

          MouseArea {
            id: mouse
            anchors.fill: parent
            enabled: parent.opacity > 0.5
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            Accessible.name: modelData.name
            onClicked: root.dashboard.moveSection(root.sectionId, modelData.offset)
          }
        }
      }

      Rectangle {
        visible: root.editing
        width: 24
        height: 23
        radius: 8
        color: deleteMouse.containsMouse ? root.dashboard.accentHover : root.dashboard.raisedSurface
        border.width: 1
        border.color: root.dashboard.surfaceBorder
        opacity: root.sectionId === "media" ? 0.4 : 1

        Text {
          anchors.centerIn: parent
          text: "×"
          color: root.dashboard.primaryText
          font.family: root.dashboard.uiFont
          font.pixelSize: 15
        }

        MouseArea {
          id: deleteMouse
          anchors.fill: parent
          enabled: parent.opacity > 0.5
          acceptedButtons: Qt.LeftButton
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          Accessible.name: "Удалить раздел " + root.title
          onClicked: root.dashboard.removeSection(root.sectionId)
        }
      }
    }

    Flow {
      visible: root.editing
      Layout.fillWidth: true
      Layout.preferredWidth: width
      spacing: 5
      Layout.preferredHeight: childrenRect.height

      Rectangle {
        width: 91
        height: 24
        radius: 10
        color: root.catalogOpen ? root.dashboard.accentSurface : root.dashboard.raisedSurface
        border.width: 1
        border.color: root.catalogOpen ? root.dashboard.accentColor : root.dashboard.surfaceBorder

        Text {
          anchors.centerIn: parent
          text: root.catalogOpen ? "− Скрыть" : "+ Добавить плитку"
          color: root.catalogOpen ? root.dashboard.accentColor : root.dashboard.primaryText
          font.family: root.dashboard.uiFont
          font.pixelSize: 9
          font.bold: true
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          cursorShape: Qt.PointingHandCursor
          onClicked: root.catalogOpen = !root.catalogOpen
        }
      }

      Text {
        visible: root.catalogOpen && root.availableTiles.length === 0
        height: 24
        verticalAlignment: Text.AlignVCenter
          text: "Все доступные плитки уже добавлены"
        color: root.dashboard.secondaryText
        font.family: root.dashboard.uiFont
        font.pixelSize: 10
      }

      Repeater {
        model: root.catalogOpen ? root.availableTiles : []

        delegate: Rectangle {
          required property string modelData
          width: Math.min(115, addLabel.implicitWidth + 20)
          height: 24
          radius: 10
          color: addMouse.containsMouse ? root.dashboard.accentHover : root.dashboard.raisedSurface
          border.width: 1
          border.color: root.dashboard.surfaceBorder

          Text {
            id: addLabel
            anchors.centerIn: parent
            text: "+ " + root.dashboard.tileLabel(modelData, true)
            color: root.dashboard.primaryText
            font.family: root.dashboard.uiFont
            font.pixelSize: 9
            font.bold: true
          }

          MouseArea {
            id: addMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            Accessible.name: "Добавить " + root.dashboard.tileLabel(modelData, false)
            onClicked: root.dashboard.addTile(modelData, root.sectionId)
          }
        }
      }
    }

    GridLayout {
      Layout.fillWidth: true
      columns: 2
      uniformCellWidths: true
      columnSpacing: 10
      rowSpacing: 10

      Repeater {
        model: root.tileIds

        delegate: WidgetTile {
          required property string modelData

          tileId: modelData
          sectionId: root.sectionId
          dashboard: root.dashboard
          dragLayer: root.dragLayer
          editing: root.editing
          Layout.fillWidth: true
          Layout.preferredWidth: root.dashboard.tileSize(tileId).columns === 1
            ? Math.max(1, (root.width - 10) / 2)
            : root.width
          Layout.maximumWidth: root.dashboard.tileSize(tileId).columns === 1
            ? Math.max(1, (root.width - 10) / 2)
            : root.width
          Layout.preferredHeight: root.dashboard.tileHeight(tileId, root.editing)
          Layout.columnSpan: root.dashboard.tileSize(tileId).columns
          Layout.rowSpan: root.dashboard.tileSize(tileId).rows
        }
      }

      Rectangle {
        visible: root.tileIds.length === 0
        Layout.fillWidth: true
        Layout.columnSpan: 2
        Layout.preferredHeight: 68
        radius: 16
        color: root.sectionDropTarget || root.tileDropTarget
          ? root.dashboard.accentSurface
          : root.dashboard.raisedSurface
        border.width: 1
        border.color: root.sectionDropTarget || root.tileDropTarget
          ? root.dashboard.accentColor : root.dashboard.surfaceBorder

        Text {
          anchors.centerIn: parent
          text: root.editing ? "Перетащите карточку или добавьте из списка" : "В этом разделе пока нет плиток"
          color: root.dashboard.secondaryText
          font.family: root.dashboard.uiFont
          font.pixelSize: 10
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          width: parent.width - 20
        }
      }
    }
  }

  Rectangle {
    visible: root.sectionDropTarget
    x: 4
    y: root.sectionDropAfter ? root.height - height - 2 : 2
    width: Math.max(0, root.width - 8)
    height: 3
    radius: 2
    color: root.dashboard.accentColor
    z: 20
  }

  Item {
    id: dragProxy
    parent: root.dragLayer
    x: root.dragStartPosition.x + root.dragTranslation.x
    y: root.dragStartPosition.y + root.dragTranslation.y
    width: root.width
    height: root.height
    z: 1000
    opacity: 0.01
    visible: root.dragInProgress

    Drag.active: root.dragInProgress
    Drag.source: root
    Drag.keys: ["omarchy-widget-section"]
    Drag.supportedActions: Qt.MoveAction
    Drag.proposedAction: Qt.MoveAction
    Drag.hotSpot.x: Math.round(root.dragHotSpot.x)
    Drag.hotSpot.y: Math.round(root.dragHotSpot.y)
  }

  Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
  Behavior on opacity { NumberAnimation { duration: 130 } }
  Behavior on x {
    enabled: !root.dragInProgress
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }
  Behavior on y {
    enabled: !root.dragInProgress
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  Component {
    id: displaySectionTitle

    Text {
      text: root.title
      color: root.dashboard.primaryText
      font.family: root.dashboard.uiFont
      font.pixelSize: 14
      font.bold: true
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }
  }

  Component {
    id: editSectionTitle

    Rectangle {
      radius: 8
      color: root.dashboard.raisedSurface
      border.width: 1
      border.color: root.dashboard.surfaceBorder

      TextInput {
        id: titleInput
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        verticalAlignment: TextInput.AlignVCenter
        text: root.title
        color: root.dashboard.primaryText
        font.family: root.dashboard.uiFont
        font.pixelSize: 12
        font.bold: true
        selectByMouse: true
        clip: true
        onEditingFinished: root.dashboard.renameSection(root.sectionId, text)
      }
    }
  }
}
