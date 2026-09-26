import QtQuick
import QtQuick.Layouts

Item {
  id: root

  property string tileId: ""
  property string sectionId: ""
  property var dashboard: null
  property Item dragLayer: null
  property bool editing: false
  property bool dropTarget: false
  property bool dropAfter: false
  property bool dragInProgress: false
  property point dragStartPosition: Qt.point(0, 0)
  property point dragHotSpot: Qt.point(0, 0)
  property point dragTranslation: Qt.point(0, 0)
  property Item pendingDropSectionTarget: null
  property Item pendingDropTileTarget: null
  property bool pendingDropAfterTile: false
  readonly property string dragType: "tile"

  readonly property bool isWide: dashboard ? dashboard.tileSize(tileId).columns === 2 : false
  readonly property bool hasMetricLevel: tileId === "cpu" || tileId === "gpu" || tileId === "network"
  readonly property real metricLevel: tileId === "cpu"
    ? dashboard.cpuLoad
    : tileId === "gpu" ? dashboard.gpuLoad : dashboard.netLoad

  function containsDragPoint(target, x, y) {
    if (!target || !root.dragLayer) return false
    var point = target.mapFromItem(root.dragLayer, x, y)
    return point.x >= 0 && point.y >= 0 && point.x <= target.width && point.y <= target.height
  }

  implicitWidth: 210
  implicitHeight: dashboard ? dashboard.tileHeight(tileId, editing) : 88
  z: dragInProgress ? 10 : 0
  scale: dragInProgress ? 1.025 : 1
  opacity: dragInProgress ? 0.88 : 1
  transform: Translate {
    x: root.dragInProgress ? root.dragTranslation.x : 0
    y: root.dragInProgress ? root.dragTranslation.y : 0
    Behavior on x {
      enabled: !root.dragInProgress
      NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }
    Behavior on y {
      enabled: !root.dragInProgress
      NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }
  }

  function metricIcon() {
    if (tileId === "cpu") return "ϟ"
    if (tileId === "gpu") return "◈"
    if (tileId === "temperature") return "♨"
    return "⌁"
  }

  function metricText() {
    if (tileId === "cpu") return dashboard.cpuText
    if (tileId === "gpu") return dashboard.gpuText
    if (tileId === "temperature") return dashboard.tempText
    return dashboard.netText
  }

  function metricLabel() {
    if (tileId === "cpu") return "Процессор"
    if (tileId === "gpu") return "Графика"
    if (tileId === "temperature") return "Температура"
    return "Сеть"
  }

  function metricValue() {
    var value = metricText()
    if (tileId === "cpu") return value.replace(/^CPU\s+/, "")
    if (tileId === "gpu") return value.replace(/^GPU\s+/, "")
    if (tileId === "network") return value.replace(/^Сеть\s+/, "")
    return value
  }

  function metricColor() {
    if (tileId === "temperature") return dashboard.warmColor
    if (tileId === "network") return dashboard.successColor
    return dashboard.accentColor
  }

  function metricBadge() {
    if (tileId === "temperature") return dashboard.warmSurface
    if (tileId === "network") return dashboard.isDark ? "#FF20392F" : "#FFE5F5EC"
    return dashboard.accentSurface
  }

  function insertAfter(x, y) {
    var horizontalDistance = Math.abs(x - width / 2) / Math.max(1, width)
    var verticalDistance = Math.abs(y - height / 2) / Math.max(1, height)
    if (horizontalDistance >= verticalDistance) return x >= width / 2
    return y >= height / 2
  }

  function canAcceptDrag(source) {
    if (!source || source === root || source.dragType !== "tile") return false
    return source.tileId !== "player" || root.sectionId === "media"
  }

  Rectangle {
    id: surface
    anchors.fill: parent
    radius: root.isWide ? 20 : 16
    color: root.dashboard.tileSurface
    border.width: root.dropTarget ? 2 : 1
    border.color: root.dropTarget
      ? root.dashboard.accentColor
      : root.editing ? root.dashboard.accentColor : root.dashboard.surfaceBorder

    Behavior on border.color { ColorAnimation { duration: 150 } }
    Behavior on border.width { NumberAnimation { duration: 150 } }
  }

  Loader {
    anchors.fill: parent
    anchors.margins: root.isWide ? 16 : 12
    anchors.bottomMargin: root.editing ? 36 : (root.isWide ? 16 : 12)
    sourceComponent: root.editing ? editorContent
      : root.tileId === "weather"
      ? weatherContent
      : root.tileId === "player" ? playerContent : metricContent
  }

  Component {
    id: editorContent

    RowLayout {
      spacing: 9

      Rectangle {
        Layout.preferredWidth: 38
        Layout.preferredHeight: 38
        radius: 11
        color: root.tileId === "temperature" ? root.dashboard.warmSurface
          : root.tileId === "network" ? (root.dashboard.isDark ? "#FF20392F" : "#FFE5F5EC")
          : root.dashboard.accentSurface

        Text {
          anchors.centerIn: parent
          text: root.tileId === "weather" ? "☀" : root.tileId === "player" ? "♫" : root.metricIcon()
          color: root.tileId === "temperature" ? root.dashboard.warmColor
            : root.tileId === "network" ? root.dashboard.successColor : root.dashboard.accentColor
          font.family: root.dashboard.uiFont
          font.pixelSize: 19
          font.bold: true
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
          text: root.dashboard.tileLabel(root.tileId, false)
          color: root.dashboard.primaryText
          font.family: root.dashboard.uiFont
          font.pixelSize: 12
          font.bold: true
          Layout.fillWidth: true
          elide: Text.ElideRight
        }

        Text {
          text: root.dashboard.tileSize(root.tileId).columns + " × "
            + root.dashboard.tileSize(root.tileId).rows
          color: root.dashboard.secondaryText
          font.family: root.dashboard.uiFont
          font.pixelSize: 10
          Layout.fillWidth: true
        }
      }

      TapHandler {
        enabled: root.editing
        acceptedButtons: Qt.LeftButton
        onDoubleTapped: root.dashboard.resetTileSize(root.tileId)
      }
    }
  }

  Component {
    id: weatherContent

    ColumnLayout {
      spacing: 4

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 52
        spacing: 12

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2

          Text {
            text: "ПОГОДА СЕЙЧАС"
            color: root.dashboard.secondaryText
            font.family: root.dashboard.uiFont
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 0.8
            Layout.fillWidth: true
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
              text: root.dashboard.weatherTemp || "Загрузка…"
              color: root.dashboard.primaryText
              font.family: root.dashboard.uiFont
              font.pixelSize: 28
              font.bold: true
              Layout.alignment: Qt.AlignVCenter
            }

            Text {
              text: root.dashboard.weatherDesc || "Погодные данные"
              color: root.dashboard.primaryText
              font.family: root.dashboard.uiFont
              font.pixelSize: 12
              font.bold: true
              Layout.fillWidth: true
              elide: Text.ElideRight
              Layout.alignment: Qt.AlignVCenter
            }
          }
        }

        Rectangle {
          Layout.preferredWidth: 48
          Layout.preferredHeight: 48
          radius: 16
          color: root.dashboard.warmSurface
          border.width: 1
          border.color: root.dashboard.surfaceBorder

          Text {
            anchors.centerIn: parent
            text: root.dashboard.weatherSymbol
            color: root.dashboard.warmColor
            font.family: root.dashboard.weatherIconFont
            font.pixelSize: 30
          }
        }
      }

      Text {
        text: root.dashboard.weatherMeta || "Обновляем прогноз"
        color: root.dashboard.secondaryText
        font.family: root.dashboard.uiFont
        font.pixelSize: 11
        Layout.fillWidth: true
        elide: Text.ElideRight
      }

      Text {
        text: root.dashboard.weatherWind || "Данные о ветре появятся здесь"
        color: root.dashboard.primaryText
        font.family: root.dashboard.uiFont
        font.pixelSize: 11
        font.bold: true
        Layout.fillWidth: true
        elide: Text.ElideRight
      }
    }
  }

  Component {
    id: metricContent

    ColumnLayout {
      spacing: 5

      Item { Layout.fillHeight: true }

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 34
        spacing: 9

        Rectangle {
          Layout.preferredWidth: 34
          Layout.preferredHeight: 34
          radius: 11
          color: root.metricBadge()

          Text {
            anchors.centerIn: parent
            text: root.metricIcon()
            color: root.metricColor()
            font.family: root.dashboard.uiFont
            font.pixelSize: 17
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 1

          Text {
            text: root.metricLabel().toUpperCase()
            color: root.dashboard.secondaryText
            font.family: root.dashboard.uiFont
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 0.4
            Layout.fillWidth: true
            elide: Text.ElideRight
          }

          Text {
            text: root.metricValue()
            color: root.dashboard.primaryText
            font.family: root.dashboard.uiFont
            font.pixelSize: 13
            font.bold: true
            Layout.fillWidth: true
            elide: Text.ElideRight
          }
        }
      }

      Rectangle {
        visible: root.hasMetricLevel
        Layout.fillWidth: true
        Layout.preferredHeight: 3
        radius: 2
        color: root.dashboard.trackColor

        Rectangle {
          width: root.metricLevel < 0 ? 0 : parent.width * Math.max(0, Math.min(1, root.metricLevel))
          height: parent.height
          radius: parent.radius
          color: root.metricColor()
          Behavior on width {
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
          }
        }
      }

      Item { Layout.fillHeight: true }
    }
  }

  Component {
    id: playerContent

    ColumnLayout {
      spacing: 6

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 16

        Text {
          text: "СЕЙЧАС ИГРАЕТ"
          color: root.dashboard.secondaryText
          font.family: root.dashboard.uiFont
          font.pixelSize: 10
          font.bold: true
          font.letterSpacing: 0.8
          Layout.fillWidth: true
        }

        Rectangle {
          width: 6
          height: 6
          radius: 3
          color: root.dashboard.successColor
          visible: root.dashboard.playerStatus === "Playing"
          Layout.alignment: Qt.AlignVCenter
        }

        Text {
          text: root.dashboard.playerStatus === "Playing" ? "Играет" : root.dashboard.playerStatus === "Paused" ? "Пауза" : "Остановлено"
          color: root.dashboard.playerStatus === "Playing" ? root.dashboard.successColor : root.dashboard.secondaryText
          font.family: root.dashboard.uiFont
          font.pixelSize: 10
          font.bold: true
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 48
        spacing: 9

        Rectangle {
          Layout.preferredWidth: 46
          Layout.preferredHeight: 46
          radius: 15
          color: root.dashboard.accentSurface
          border.width: 1
          border.color: root.dashboard.surfaceBorder

          Text {
            anchors.centerIn: parent
            text: "♫"
            color: root.dashboard.accentColor
            font.family: root.dashboard.uiFont
            font.pixelSize: 22
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 1

          Text {
            text: root.dashboard.title
            color: root.dashboard.primaryText
            font.family: root.dashboard.uiFont
            font.pixelSize: 14
            font.bold: true
            Layout.fillWidth: true
            elide: Text.ElideRight
          }

          Text {
            text: root.dashboard.artist + (root.dashboard.album !== "" ? "  ·  " + root.dashboard.album : "")
            color: root.dashboard.secondaryText
            font.family: root.dashboard.uiFont
            font.pixelSize: 11
            Layout.fillWidth: true
            elide: Text.ElideRight
          }
        }
      }

      Item {
        id: seekBar
        Layout.fillWidth: true
        Layout.preferredHeight: 15
        Accessible.role: Accessible.Slider
        Accessible.name: "Позиция воспроизведения"
        Accessible.description: root.dashboard.elapsed + " из " + root.dashboard.duration

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          height: 4
          radius: 2
          color: root.dashboard.trackColor
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * root.dashboard.progress
          height: 4
          radius: 2
          color: root.dashboard.accentColor
        }

        Rectangle {
          x: Math.max(0, Math.min(parent.width - width, parent.width * root.dashboard.progress - width / 2))
          anchors.verticalCenter: parent.verticalCenter
          width: 10
          height: 10
          radius: 5
          color: root.dashboard.primaryText
          visible: root.dashboard.durationSeconds > 0
        }

        MouseArea {
          id: seekMouse
          anchors.fill: parent
          preventStealing: true
          enabled: !root.dashboard.editing && root.dashboard.durationSeconds > 0
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

          onPressed: function(mouse) {
            root.dashboard.seeking = true
            root.dashboard.seekTo(mouse.x / Math.max(1, width))
          }
          onPositionChanged: function(mouse) {
            if (pressed) root.dashboard.seekTo(mouse.x / Math.max(1, width))
          }
          onReleased: root.dashboard.endSeek()
          onCanceled: root.dashboard.endSeek()
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 14

        Text {
          text: root.dashboard.elapsed
          color: root.dashboard.secondaryText
          font.family: root.dashboard.uiFont
          font.pixelSize: 10
          Layout.fillWidth: true
        }

        Text {
          text: root.dashboard.durationSeconds > 0
            ? "−" + root.dashboard.formatTime(Math.max(0, root.dashboard.durationSeconds - root.dashboard.positionSeconds))
            : "--:--"
          color: root.dashboard.secondaryText
          font.family: root.dashboard.uiFont
          font.pixelSize: 10
          horizontalAlignment: Text.AlignRight
        }
      }

      Item {
        id: transportRow
        Layout.fillWidth: true
        Layout.preferredHeight: 42

        RowLayout {
          anchors.centerIn: parent
          spacing: 5

          Rectangle {
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            radius: 12
            color: seekBackMouse.pressed ? root.dashboard.accentHover : seekBackMouse.containsMouse ? root.dashboard.accentSurface : root.dashboard.raisedSurface
            border.width: 1
            border.color: root.dashboard.surfaceBorder
            opacity: seekBackMouse.enabled ? 1 : 0.48
            Accessible.role: Accessible.Button
            Accessible.name: "Перемотать назад на 10 секунд"

            Text {
              anchors.centerIn: parent
              text: "−10"
              color: root.dashboard.primaryText
              font.family: root.dashboard.uiFont
              font.pixelSize: 11
              font.bold: true
            }

            MouseArea {
              id: seekBackMouse
              anchors.fill: parent
              enabled: !root.dashboard.editing && root.dashboard.durationSeconds > 0
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.dashboard.seekBy(-10)
            }
          }

          Rectangle {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 40
            radius: 14
            color: playbackMouse.pressed ? root.dashboard.accentHover : playbackMouse.containsMouse ? root.dashboard.accentHover : root.dashboard.accentSurface
            border.width: 1
            border.color: root.dashboard.accentColor
            opacity: playbackMouse.enabled ? 1 : 0.48
            Accessible.role: Accessible.Button
            Accessible.name: root.dashboard.playerStatus === "Playing" ? "Пауза" : "Воспроизвести"
            Accessible.description: "Нажатие переключает воспроизведение и паузу. Удержание или правая кнопка останавливает трек."

            Text {
              anchors.centerIn: parent
              text: root.dashboard.playerStatus === "Playing" ? "Ⅱ" : "▶"
              color: root.dashboard.accentColor
              font.family: root.dashboard.uiFont
              font.pixelSize: 19
              font.bold: true
            }

            MouseArea {
              id: playbackMouse
              anchors.fill: parent
              enabled: !root.dashboard.editing
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              property bool holdTriggered: false
              Accessible.role: Accessible.Button
              Accessible.name: root.dashboard.playerStatus === "Playing" ? "Пауза" : "Воспроизвести"
              Accessible.description: "Удерживайте, чтобы остановить трек."
              onPressed: holdTriggered = false
              onPressAndHold: function(mouse) {
                if (mouse.button !== Qt.LeftButton) return
                holdTriggered = true
                root.dashboard.stopPlayback()
              }
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                  root.dashboard.stopPlayback()
                } else if (!holdTriggered) {
                  root.dashboard.togglePlayback()
                }
                holdTriggered = false
              }
            }
          }

          Rectangle {
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            radius: 12
            color: seekForwardMouse.pressed ? root.dashboard.accentHover : seekForwardMouse.containsMouse ? root.dashboard.accentSurface : root.dashboard.raisedSurface
            border.width: 1
            border.color: root.dashboard.surfaceBorder
            opacity: seekForwardMouse.enabled ? 1 : 0.48
            Accessible.role: Accessible.Button
            Accessible.name: "Перемотать вперёд на 10 секунд"

            Text {
              anchors.centerIn: parent
              text: "+10"
              color: root.dashboard.primaryText
              font.family: root.dashboard.uiFont
              font.pixelSize: 11
              font.bold: true
            }

            MouseArea {
              id: seekForwardMouse
              anchors.fill: parent
              enabled: !root.dashboard.editing && root.dashboard.durationSeconds > 0
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.dashboard.seekBy(10)
            }
          }

          Rectangle {
            Layout.preferredWidth: 26
            Layout.preferredHeight: 30
            radius: 10
            color: muteMouse.pressed ? root.dashboard.accentHover : muteMouse.containsMouse ? root.dashboard.accentSurface : "transparent"
            border.width: 1
            border.color: muteMouse.containsMouse ? root.dashboard.surfaceBorder : "transparent"
            opacity: muteMouse.enabled ? 1 : 0.48
            Accessible.role: Accessible.Button
            Accessible.name: root.dashboard.playerVolume > 0 ? "Выключить звук" : "Включить звук"

            Text {
              anchors.centerIn: parent
              text: root.dashboard.playerVolume > 0 ? "◖))" : "◖×"
              color: root.dashboard.accentColor
              font.family: root.dashboard.uiFont
              font.pixelSize: 11
            }

            MouseArea {
              id: muteMouse
              anchors.fill: parent
              enabled: !root.dashboard.editing && root.dashboard.playerVolumeAvailable
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              Accessible.role: Accessible.Button
              Accessible.name: root.dashboard.playerVolume > 0 ? "Выключить звук" : "Включить звук"
              onClicked: root.dashboard.toggleMute()
            }
          }

          Rectangle {
            Layout.preferredWidth: 24
            Layout.preferredHeight: 28
            radius: 9
            color: volumeDownMouse.pressed ? root.dashboard.accentHover : volumeDownMouse.containsMouse ? root.dashboard.accentSurface : root.dashboard.raisedSurface
            border.width: 1
            border.color: root.dashboard.surfaceBorder
            opacity: volumeDownMouse.enabled ? 1 : 0.48
            Accessible.role: Accessible.Button
            Accessible.name: "Уменьшить громкость плеера на 5 процентов"

            Text {
              anchors.centerIn: parent
              text: "−"
              color: root.dashboard.primaryText
              font.family: root.dashboard.uiFont
              font.pixelSize: 14
            }

            MouseArea {
              id: volumeDownMouse
              anchors.fill: parent
              enabled: !root.dashboard.editing && root.dashboard.playerVolumeAvailable
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.dashboard.setPlayerVolume(root.dashboard.playerVolume - 0.05)
            }
          }

          Item {
            id: volumeBar
            Layout.preferredWidth: 120
            Layout.minimumWidth: 90
            Layout.maximumWidth: 120
            Layout.preferredHeight: 30
            Accessible.role: Accessible.Slider
            Accessible.name: "Громкость медиаплеера"
            Accessible.description: root.dashboard.playerVolumeAvailable ? Math.round(root.dashboard.playerVolume * 100) + "%" : "Недоступно"

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              height: 4
              radius: 2
              color: root.dashboard.trackColor
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: root.dashboard.playerVolumeAvailable ? parent.width * root.dashboard.playerVolume : 0
              height: 4
              radius: 2
              color: root.dashboard.accentColor
            }

            Rectangle {
              x: Math.max(0, Math.min(parent.width - width, parent.width * root.dashboard.playerVolume - width / 2))
              anchors.verticalCenter: parent.verticalCenter
              width: 10
              height: 10
              radius: 5
              color: root.dashboard.primaryText
              visible: root.dashboard.playerVolumeAvailable
            }

            MouseArea {
              id: volumeMouse
              anchors.fill: parent
              preventStealing: true
              enabled: !root.dashboard.editing && root.dashboard.playerVolumeAvailable
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onPressed: function(mouse) {
                root.dashboard.previewPlayerVolume(mouse.x / Math.max(1, width))
              }
              onPositionChanged: function(mouse) {
                if (pressed) root.dashboard.previewPlayerVolume(mouse.x / Math.max(1, width))
              }
              onReleased: root.dashboard.endPlayerVolume()
              onCanceled: root.dashboard.endPlayerVolume()
            }
          }

          Rectangle {
            Layout.preferredWidth: 24
            Layout.preferredHeight: 28
            radius: 9
            color: volumeUpMouse.pressed ? root.dashboard.accentHover : volumeUpMouse.containsMouse ? root.dashboard.accentSurface : root.dashboard.raisedSurface
            border.width: 1
            border.color: root.dashboard.surfaceBorder
            opacity: volumeUpMouse.enabled ? 1 : 0.48
            Accessible.role: Accessible.Button
            Accessible.name: "Увеличить громкость плеера на 5 процентов"

            Text {
              anchors.centerIn: parent
              text: "+"
              color: root.dashboard.primaryText
              font.family: root.dashboard.uiFont
              font.pixelSize: 14
            }

            MouseArea {
              id: volumeUpMouse
              anchors.fill: parent
              enabled: !root.dashboard.editing && root.dashboard.playerVolumeAvailable
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.dashboard.setPlayerVolume(root.dashboard.playerVolume + 0.05)
            }
          }

          Text {
            text: root.dashboard.playerVolumeAvailable ? Math.round(root.dashboard.playerVolume * 100) + "%" : "—"
            color: root.dashboard.playerVolumeAvailable ? root.dashboard.primaryText : root.dashboard.secondaryText
            font.family: root.dashboard.uiFont
            font.pixelSize: 10
            font.bold: true
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 32
            Layout.alignment: Qt.AlignVCenter
          }
        }
      }
    }
  }

  Row {
    visible: root.editing
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: 10
    anchors.bottomMargin: 7
    spacing: 3
    z: 6

    Repeater {
      model: ["Ш−", "Ш+", "В−", "В+", "↺", "×"]

      delegate: Rectangle {
        required property string modelData
        required property int index
        readonly property var size: root.dashboard.tileSize(root.tileId)
        readonly property bool isSizeAction: index < 4
        readonly property bool isAvailable: index === 0 ? size.columns > 1 && root.tileId !== "player"
          : index === 1 ? size.columns < 2 && root.tileId !== "player"
          : index === 2 ? size.rows > 1
          : index === 3 ? size.rows < 2
          : index === 4 ? size.columns !== (root.tileId === "weather" || root.tileId === "player" ? 2 : 1) || size.rows !== 1
          : root.tileId !== "player"
        width: 29
        height: 24
        radius: 8
        color: actionMouse.containsMouse ? root.dashboard.accentHover : root.dashboard.raisedSurface
        border.width: 1
        border.color: root.dashboard.surfaceBorder
        opacity: isAvailable ? 1 : 0.4

        Text {
          anchors.centerIn: parent
          text: modelData
          color: root.dashboard.primaryText
          font.family: root.dashboard.uiFont
          font.pixelSize: 9
          font.bold: true
        }

        MouseArea {
          id: actionMouse
          anchors.fill: parent
          enabled: parent.isAvailable
          acceptedButtons: Qt.LeftButton
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          Accessible.name: index === 0 ? "Уменьшить ширину" : index === 1 ? "Увеличить ширину"
            : index === 2 ? "Уменьшить высоту" : index === 3 ? "Увеличить высоту"
            : index === 4 ? "Вернуть размер плитки по умолчанию" : "Удалить плитку"
          onClicked: {
            if (index === 0) root.dashboard.resizeTile(root.tileId, -1, 0)
            else if (index === 1) root.dashboard.resizeTile(root.tileId, 1, 0)
            else if (index === 2) root.dashboard.resizeTile(root.tileId, 0, -1)
            else if (index === 3) root.dashboard.resizeTile(root.tileId, 0, 1)
            else if (index === 4) root.dashboard.resetTileSize(root.tileId)
            else root.dashboard.removeTile(root.tileId)
          }
        }
      }
    }
  }

  Rectangle {
    visible: root.dropTarget
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: 10
    width: 72
    height: 24
    radius: 12
    color: root.dashboard.accentColor

    Text {
      anchors.centerIn: parent
      text: root.dropAfter ? "ПОСЛЕ" : "ПЕРЕД"
      color: "white"
      font.family: root.dashboard.uiFont
      font.pixelSize: 9
      font.bold: true
      font.letterSpacing: 0.3
    }
  }

  DragHandler {
    id: tileDrag
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
        root.dragHotSpot = Qt.point(tileDrag.centroid.position.x, tileDrag.centroid.position.y)
        root.pendingDropSectionTarget = null
        root.pendingDropTileTarget = null
        root.pendingDropAfterTile = false
        root.dragInProgress = true
        root.dashboard.draggingItems = true
      } else if (root.dragInProgress) {
        var pointX = root.dragStartPosition.x + root.dragTranslation.x + root.dragHotSpot.x
        var pointY = root.dragStartPosition.y + root.dragTranslation.y + root.dragHotSpot.y
        var tileTarget = root.pendingDropTileTarget
        var sectionTarget = root.pendingDropSectionTarget
        var useTileTarget = root.containsDragPoint(tileTarget, pointX, pointY)
        var useSectionTarget = !useTileTarget && root.containsDragPoint(sectionTarget, pointX, pointY)
        var targetSectionId = useTileTarget ? tileTarget.sectionId
          : useSectionTarget ? sectionTarget.sectionId : ""
        var targetTileId = useTileTarget ? tileTarget.tileId : ""
        var targetAfter = useTileTarget ? root.pendingDropAfterTile : true
        root.pendingDropSectionTarget = null
        root.pendingDropTileTarget = null
        root.dragInProgress = false
        root.dashboard.draggingItems = false
        if (targetSectionId !== "" && root.tileId !== "player") {
          root.dashboard.moveTile(root.tileId, targetSectionId, targetTileId, targetAfter)
        }
      }
    }
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
    Drag.keys: ["omarchy-widget-tile"]
    Drag.supportedActions: Qt.MoveAction
    Drag.proposedAction: Qt.MoveAction
    Drag.hotSpot.x: Math.round(root.dragHotSpot.x)
    Drag.hotSpot.y: Math.round(root.dragHotSpot.y)
  }

  DropArea {
    id: tileDrop
    anchors.fill: parent
    z: 5
    enabled: root.editing && !root.dashboard.widgetLayout.locked && !root.dragInProgress
    keys: ["omarchy-widget-tile"]

    onEntered: function(drop) {
      if (!root.canAcceptDrag(drop.source)) return
      drop.acceptProposedAction()
      root.dropTarget = true
      root.dropAfter = root.insertAfter(drop.x, drop.y)
      drop.source.pendingDropTileTarget = root
      drop.source.pendingDropAfterTile = root.dropAfter
    }
    onPositionChanged: function(drop) {
      if (!root.canAcceptDrag(drop.source)) return
      drop.acceptProposedAction()
      root.dropTarget = true
      root.dropAfter = root.insertAfter(drop.x, drop.y)
      drop.source.pendingDropTileTarget = root
      drop.source.pendingDropAfterTile = root.dropAfter
    }
    onExited: {
      root.dropTarget = false
    }
    onDropped: function(drop) {
      if (!root.canAcceptDrag(drop.source)) return
      drop.accept(Qt.MoveAction)
      root.dashboard.moveTile(drop.source.tileId, root.sectionId, root.tileId, root.dropAfter)
      root.dropTarget = false
    }
  }

  Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
  Behavior on opacity { NumberAnimation { duration: 130 } }
  Behavior on x {
    enabled: !root.dragInProgress
    NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
  }
  Behavior on y {
    enabled: !root.dragInProgress
    NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
  }
}
