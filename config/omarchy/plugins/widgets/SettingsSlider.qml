import QtQuick
import QtQuick.Layouts

Item {
  id: root

  property string label: ""
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property color accent: "#8758e8"
  property color track: "#dde4de"
  property color textColor: "#202723"
  property color mutedColor: "#68736d"
  signal valueEdited(real value)

  readonly property real normalizedValue: Math.max(0, Math.min(1,
    (value - minimum) / Math.max(0.0001, maximum - minimum)))

  implicitHeight: 47

  ColumnLayout {
    anchors.fill: parent
    spacing: 3

    RowLayout {
      Layout.fillWidth: true
      Layout.preferredHeight: 16

      Text {
        text: root.label
        color: root.textColor
        font.family: "Noto Sans"
        font.pixelSize: 11
        font.bold: true
        Layout.fillWidth: true
        elide: Text.ElideRight
      }

      Text {
        text: Math.round(root.value * 100) + "%"
        color: root.mutedColor
        font.family: "Noto Sans"
        font.pixelSize: 10
        font.bold: true
      }
    }

    Item {
      id: trackArea
      Layout.fillWidth: true
      Layout.fillHeight: true
      implicitHeight: 24

      Rectangle {
        x: 5
        y: (parent.height - 5) / 2
        width: Math.max(0, (parent.width - 10) * root.normalizedValue)
        height: 5
        radius: 3
        color: root.accent
      }

      Rectangle {
        x: 5 + Math.max(0, parent.width - 10) * root.normalizedValue
        y: (parent.height - 5) / 2
        width: Math.max(0, parent.width - 10) * (1 - root.normalizedValue)
        height: 5
        radius: 3
        color: root.track
      }

      Rectangle {
        x: 5 + Math.max(0, parent.width - 10) * root.normalizedValue - width / 2
        y: (parent.height - height) / 2
        width: 13
        height: 13
        radius: 7
        color: root.accent
        border.width: 2
        border.color: root.textColor
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        Accessible.name: root.label + ", " + Math.round(root.value * 100) + "%"

        function updateValue(x) {
          var ratio = Math.max(0, Math.min(1, (x - 5) / Math.max(1, width - 10)))
          root.valueEdited(root.minimum + ratio * (root.maximum - root.minimum))
        }

        onPressed: function(mouse) { updateValue(mouse.x) }
        onPositionChanged: function(mouse) { if (pressed) updateValue(mouse.x) }
      }
    }
  }
}
