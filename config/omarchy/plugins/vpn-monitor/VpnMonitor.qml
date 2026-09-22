import QtQuick
import QtQuick.Layouts
import "VpnUiModel.js" as Ui

pragma ComponentBehavior: Bound

Item {
  id: root
  property var status: ({}) // Sole input: backend result. No local system probing.
  property bool busy: false
  property var request: function(action) {} // Parent supplies local-API request dispatcher.
  readonly property var uiStatus: ({ client: status.client || {}, connection: status.connection || {}, capabilities: status.capabilities || {}, busy: busy })
  readonly property var allowed: Ui.buttons(uiStatus)
  readonly property string connectionState: String((status.connection || {}).state || "UNKNOWN")

  implicitWidth: 410
  implicitHeight: column.implicitHeight
  ColumnLayout {
    id: column
    anchors.fill: parent
    spacing: 8
    Text { text: String((root.status.client || {}).name || "VPN") + " · " + Ui.label(root.connectionState); color: Ui.color(root.connectionState); font.bold: true; font.pixelSize: 16 }
    Text { text: "Интерфейс: " + String((root.status.interface || {}).name || "не найден") + " · " + String((root.status.interface || {}).state || "NOT_FOUND"); color: "#a8b0b8" }
    Text { text: "↓ " + Number((root.status.traffic || {}).downloadMbps || 0).toFixed(2) + " Mbit/s   ↑ " + Number((root.status.traffic || {}).uploadMbps || 0).toFixed(2) + " Mbit/s"; color: "#d9e1e8" }
    Text { text: "Получено: " + Number((root.status.traffic || {}).inputBytes || 0) + " B · Отправлено: " + Number((root.status.traffic || {}).outputBytes || 0) + " B"; color: "#a8b0b8" }
    Text { text: "Интернет: " + ((root.status.diagnostics || {}).internetAvailable ? "доступен" : "не проверен/недоступен"); color: "#a8b0b8" }
    RowLayout {
      spacing: 6
      Repeater {
        model: [
          { text: "Старт", action: "start", enabled: root.allowed.start },
          { text: "Стоп", action: "stop", enabled: root.allowed.stop },
          { text: "Подключить", action: "connect", enabled: root.allowed.connect },
          { text: "Отключить", action: "disconnect", enabled: root.allowed.disconnect },
          { text: "Проверить", action: "diagnostics", enabled: root.allowed.ping }
        ]
        delegate: Rectangle {
          required property var modelData
          id: actionButton
          implicitWidth: label.implicitWidth + 18; implicitHeight: 28; radius: 14
          color: modelData.enabled ? "#355d7a" : "#303840"; opacity: modelData.enabled ? 1 : .55
          Text { id: label; anchors.centerIn: parent; text: parent.modelData.text; color: "white"; font.pixelSize: 11 }
          MouseArea { anchors.fill: parent; enabled: actionButton.modelData.enabled; onClicked: root.request(actionButton.modelData.action) }
        }
      }
    }
    Text { visible: !(root.status.capabilities || {}).toggleInterface; text: "Управление интерфейсом выполняется самим VPN-клиентом"; color: "#a8b0b8"; font.pixelSize: 11; wrapMode: Text.Wrap }
  }
}
