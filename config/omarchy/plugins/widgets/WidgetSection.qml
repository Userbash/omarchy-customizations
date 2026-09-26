import QtQuick
import QtQuick.Layouts

Item {
  id: root

  property string sectionId: ""
  property string title: ""
  property var tileIds: []
  property var availableTiles: []
  property var dashboard: null
  property bool editing: false
  property bool catalogOpen: false
  readonly property bool containsDrag: sectionDrop.containsDrag

  implicitWidth: 440
  implicitHeight: sectionLayout.implicitHeight

  DropArea {
    id: sectionDrop
    anchors.fill: parent
    z: -1
    enabled: root.editing
    keys: ["omarchy-widget-tile"]

    onDropped: function(drop) {
      if (!drop.source || !drop.source.tileId) return
      root.dashboard.moveTile(drop.source.tileId, root.sectionId, "", true)
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
            ? 0.4 : 1

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
        visible: root.availableTiles.length === 0
        height: 24
        verticalAlignment: Text.AlignVCenter
        text: "Все плитки добавлены"
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
        color: sectionDrop.containsDrag
          ? root.dashboard.accentSurface
          : root.dashboard.raisedSurface
        border.width: 1
        border.color: sectionDrop.containsDrag ? root.dashboard.accentColor : root.dashboard.surfaceBorder

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
