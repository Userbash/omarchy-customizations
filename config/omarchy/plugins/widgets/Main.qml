import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "TileLayout.js" as TileLayout

Item {
  id: root

  readonly property string uiFont: "Noto Sans"
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/widgets"
  readonly property string layoutDirectory: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/widgets"
  readonly property string layoutPath: layoutDirectory + "/layout.json"
  readonly property var themeOptions: [
    { mode: "auto", label: "Авто" },
    { mode: "light", label: "Светлая" },
    { mode: "dark", label: "Тёмная" }
  ]
  readonly property var tileOptions: [
    { id: "weather", label: "Погода", shortLabel: "Погода" },
    { id: "cpu", label: "Процессор", shortLabel: "CPU" },
    { id: "gpu", label: "Графика", shortLabel: "Графика" },
    { id: "temperature", label: "Температура", shortLabel: "Темп." },
    { id: "network", label: "Сеть", shortLabel: "Сеть" },
    { id: "player", label: "Медиаплеер", shortLabel: "Медиа" }
  ]
  readonly property var weatherIconOptions: [
    { id: "minimal", label: "Лаконичные", sample: "☀" },
    { id: "color", label: "Цветные", sample: "🌤️" }
  ]

  property string weatherTemp: ""
  property string weatherDesc: ""
  property string weatherMeta: ""
  property string weatherWind: ""
  property real weatherCode: 0
  property real weatherIsDay: 1
  property string cpuText: "CPU  —"
  property string gpuText: "GPU  —"
  property string tempText: "CPU temp  —"
  property string netText: "Сеть  —"
  property real cpuLoad: -1
  property real gpuLoad: -1
  property real netLoad: -1
  property string artist: "Ничего не воспроизводится"
  property string title: "Запустите плеер, чтобы увидеть текущий трек"
  property string album: ""
  property string playerStatus: "Stopped"
  property string elapsed: "0:00"
  property string duration: "0:00"
  property real progress: 0
  property real positionSeconds: 0
  property real durationSeconds: 0
  property real playerVolume: 1
  property real rememberedPlayerVolume: 0.5
  property string playerTarget: ""
  property bool playerVolumeAvailable: false
  property bool adjustingPlayerVolume: false
  property bool volumeWritePending: false
  property bool queuedVolumeWrite: false
  property bool volumeReadQueued: false
  property real queuedPlayerVolume: 0
  property int volumeWriteRevision: 0
  property int volumeReadRevision: 0
  property bool seeking: false
  property bool editing: false
  property bool draggingItems: false
  property string editorTab: "layout"
  property bool sectionCreateOpen: false
  property string sectionDraftTitle: ""
  property bool layoutLoaded: false
  property var widgetLayout: TileLayout.defaultLayout()
  property var previousCpu: null
  property var previousNet: null
  property double previousNetAt: 0

  SystemPalette {
    id: systemPalette
    colorGroup: SystemPalette.Active
  }

  readonly property bool systemPrefersDark:
    (0.2126 * systemPalette.window.r + 0.7152 * systemPalette.window.g + 0.0722 * systemPalette.window.b) < 0.48
  readonly property bool isDark:
    widgetLayout.theme === "dark" || (widgetLayout.theme === "auto" && systemPrefersDark)
  readonly property color panelSurface: isDark
    ? Qt.rgba(0.067, 0.082, 0.075, widgetLayout.appearance.panelOpacity)
    : Qt.rgba(0.945, 0.953, 0.941, widgetLayout.appearance.panelOpacity)
  readonly property color panelBorder: isDark ? "#FF303934" : "#FFE2E7E2"
  readonly property color tileSurface: isDark
    ? Qt.rgba(0.125, 0.153, 0.137, widgetLayout.appearance.tileOpacity)
    : Qt.rgba(1, 1, 1, widgetLayout.appearance.tileOpacity)
  readonly property color raisedSurface: isDark ? "#FF282F2B" : "#FFF2F4F1"
  readonly property color surfaceBorder: isDark ? "#FF303934" : "#FFE7EBE6"
  readonly property color primaryText: isDark ? "#FFF1F4F0" : "#FF202723"
  readonly property color secondaryText: isDark ? "#FFA0AAA4" : "#FF68736D"
  readonly property color accentColor: isDark ? "#FFAA85FF" : "#FF8758E8"
  readonly property color accentSurface: isDark ? "#FF352B49" : "#FFF0EAFF"
  readonly property color accentHover: isDark ? "#FF443754" : "#FFE4D9FF"
  readonly property color successColor: isDark ? "#FF51D49A" : "#FF238A63"
  readonly property color warmColor: isDark ? "#FFFFC870" : "#FF9D691D"
  readonly property color warmSurface: isDark ? "#FF3D3323" : "#FFFFF2D9"
  readonly property color trackColor: isDark ? "#FF3A443E" : "#FFDDE4DE"
  readonly property string wallpaperId: widgetLayout.appearance.wallpapers[isDark ? "dark" : "light"]
  readonly property real wallpaperOpacity: widgetLayout.appearance.wallpaperOpacity[isDark ? "dark" : "light"]
  readonly property string wallpaperUrl: Qt.resolvedUrl("backgrounds/" + wallpaperId + ".svg")
  readonly property string weatherSymbol: weatherIcon(weatherCode, weatherIsDay)
  readonly property string weatherIconFont: widgetLayout.appearance.weatherIconSet === "color" ? "Noto Color Emoji" : uiFont

  function formatTime(value) {
    var seconds = Math.max(0, Math.floor(Number(value) || 0))
    return Math.floor(seconds / 60) + ":" + ("0" + (seconds % 60)).slice(-2)
  }

  function playerCommand(action, value) {
    var command = ["sh", root.pluginDir + "/player-control.sh", action]
    if (action === "position" || action === "volume-set") {
      command.push(Number(value).toFixed(action === "position" ? 3 : 2))
    }
    if (root.playerTarget !== "") command.push(root.playerTarget)
    control.command = command
    control.running = true
    playerPoll.restart()
  }

  function togglePlayback() {
    playerCommand(playerStatus === "Playing" ? "pause" : "play")
  }

  function stopPlayback() {
    playerCommand("stop")
  }

  function seekTo(ratio) {
    var durationValue = Number(durationSeconds)
    ratio = Number(ratio)
    if (!isFinite(durationValue) || durationValue <= 0 || !isFinite(ratio)) return
    ratio = Math.max(0, Math.min(1, ratio))
    positionSeconds = durationValue * ratio
    progress = ratio
    elapsed = formatTime(positionSeconds)
  }

  function endSeek() {
    if (!seeking || durationSeconds <= 0) return
    seeking = false
    playerCommand("position", positionSeconds)
  }

  function seekBy(offset) {
    var durationValue = Number(durationSeconds)
    offset = Number(offset)
    if (!isFinite(durationValue) || durationValue <= 0 || !isFinite(offset)) return
    positionSeconds = Math.max(0, Math.min(durationValue, positionSeconds + offset))
    progress = positionSeconds / durationValue
    elapsed = formatTime(positionSeconds)
    playerCommand("position", positionSeconds)
  }

  function applyPlayerVolume(value, revision) {
    if (volumeWritePending || adjustingPlayerVolume || Number(revision) < volumeWriteRevision) return
    var result = String(value).trim().split("§")
    if (result.length > 1) {
      if (playerTarget !== "" && result[0] !== playerTarget) return
      if (playerTarget === "") playerTarget = result[0]
    }
    var volume = Number(result.length > 1 ? result[1] : result[0])
    if (!isFinite(volume) || volume < 0 || volume > 1) {
      playerVolumeAvailable = false
      return
    }
    playerVolumeAvailable = true
    if (!adjustingPlayerVolume) {
      playerVolume = volume
      if (volume > 0) rememberedPlayerVolume = volume
    }
  }

  function previewPlayerVolume(ratio) {
    ratio = Number(ratio)
    if (!playerVolumeAvailable || !isFinite(ratio)) return
    playerVolume = Math.max(0, Math.min(1, ratio))
    if (playerVolume > 0) rememberedPlayerVolume = playerVolume
    adjustingPlayerVolume = true
  }

  function endPlayerVolume() {
    if (!adjustingPlayerVolume) return
    adjustingPlayerVolume = false
    writePlayerVolume(playerVolume)
  }

  function setPlayerVolume(value) {
    value = Number(value)
    if (!playerVolumeAvailable || !isFinite(value)) return
    playerVolume = Math.max(0, Math.min(1, value))
    if (playerVolume > 0) rememberedPlayerVolume = playerVolume
    writePlayerVolume(playerVolume)
  }

  function writePlayerVolume(value) {
    value = Math.max(0, Math.min(1, Number(value)))
    if (!isFinite(value) || !playerVolumeAvailable) return
    playerVolume = value
    if (value > 0) rememberedPlayerVolume = value
    volumeWriteRevision += 1
    if (volumeWriteProcess.running) {
      queuedPlayerVolume = value
      queuedVolumeWrite = true
      volumeWritePending = true
      return
    }
    volumeWritePending = true
    var command = ["sh", root.pluginDir + "/player-control.sh", "volume-set", value.toFixed(2)]
    if (root.playerTarget !== "") command.push(root.playerTarget)
    volumeWriteProcess.command = command
    volumeWriteProcess.running = true
  }

  function finishPlayerVolumeWrite(exitCode) {
    if (queuedVolumeWrite) {
      var nextVolume = queuedPlayerVolume
      queuedVolumeWrite = false
      writePlayerVolume(nextVolume)
      return
    }
    volumeWritePending = false
    if (exitCode !== 0) playerVolumeAvailable = false
    playerVolumeRefresh.restart()
  }

  function requestPlayerVolume() {
    if (volumeWritePending) return
    if (playerVolumeProcess.running) {
      volumeReadQueued = true
      return
    }
    volumeReadQueued = false
    volumeReadRevision = volumeWriteRevision
    playerVolumeProcess.command = playerTarget === ""
      ? ["sh", root.pluginDir + "/player-control.sh", "volume-get"]
      : ["sh", root.pluginDir + "/player-control.sh", "volume-get", playerTarget]
    playerVolumeProcess.running = true
  }

  function finishPlayerVolumeRead() {
    if (volumeReadQueued && !volumeWritePending) requestPlayerVolume()
  }

  function toggleMute() {
    if (!playerVolumeAvailable) return
    if (playerVolume > 0) {
      rememberedPlayerVolume = playerVolume
      setPlayerVolume(0)
      return
    }
    setPlayerVolume(rememberedPlayerVolume > 0 ? rememberedPlayerVolume : 0.5)
  }

  function weatherLabel(code) {
    code = Number(code)
    if (code === 0) return "ясно"
    if (code === 1) return "преимущественно ясно"
    if (code === 2) return "переменная облачность"
    if (code === 3) return "облачно"
    if (code === 45 || code === 48) return "туман"
    if (code === 56 || code === 57 || code === 66 || code === 67) return "дождь со снегом"
    if (code <= 55) return "морось"
    if (code <= 65) return "дождь"
    if (code <= 77) return "снег"
    if (code <= 82) return "ливень"
    if (code <= 86) return "снегопад"
    return "гроза"
  }

  function windDirection(degrees) {
    var directions = ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"]
    return directions[Math.round((((Number(degrees) % 360) + 360) % 360) / 45) % 8]
  }

  function weatherIcon(code, isDay) {
    code = Number(code)
    if (widgetLayout.appearance.weatherIconSet === "color") {
      if (code === 0) return Number(isDay) === 1 ? "☀️" : "🌙"
      if (code === 1 || code === 2) return "🌤️"
      if (code === 3) return "☁️"
      if (code === 45 || code === 48) return "🌫️"
      if (code === 56 || code === 57 || code === 66 || code === 67) return "🌨️"
      if (code <= 55) return "🌦️"
      if (code <= 65) return "🌧️"
      if (code <= 77) return "❄️"
      if (code <= 82) return "🌧️"
      if (code <= 86) return "🌨️"
      return "⛈️"
    }
    if (code === 0) return Number(isDay) === 1 ? "☀" : "☾"
    if (code === 1 || code === 2) return "◐"
    if (code === 3) return "☁"
    if (code === 45 || code === 48) return "≋"
    if (code === 56 || code === 57 || code === 66 || code === 67) return "❅"
    if (code <= 55) return "⸬"
    if (code <= 65) return "☂"
    if (code <= 77) return "❄"
    if (code <= 82) return "☂"
    if (code <= 86) return "❄"
    return "ϟ"
  }

  function applyWeather(line) {
    var values = String(line).trim().split(/\s+/)
    if (values.length < 9 || !isFinite(Number(values[0]))) return

    var temperature = Math.round(Number(values[0]))
    weatherCode = Number(values[6])
    weatherIsDay = Number(values[7])
    weatherTemp = (temperature > 0 ? "+" : "") + temperature + "°C"
    weatherDesc = weatherLabel(values[6])
    weatherMeta = "Ощущается " + Math.round(Number(values[1])) + "°C   ·   Влажность "
      + Math.round(Number(values[2])) + "%   ·   Осадки " + Number(values[3]).toFixed(1) + " мм"
    weatherWind = "Ветер " + Number(values[4]).toFixed(1) + " м/с  " + windDirection(values[5])
  }

  function wallpaperOptions(theme) {
    return theme === "light"
      ? [
          { id: "light-sakura", label: "Сакура · рассвет" },
          { id: "light-evening", label: "Вечерний берег" }
        ]
      : [
          { id: "dark-orbit", label: "Орбитальная ночь" },
          { id: "dark-forest", label: "Лунный лес" }
        ]
  }

  function tileLabel(tileId, shortForm) {
    for (var index = 0; index < tileOptions.length; index += 1) {
      if (tileOptions[index].id === tileId) return shortForm ? tileOptions[index].shortLabel : tileOptions[index].label
    }
    return tileId
  }

  function tileSize(tileId) {
    return widgetLayout.tileSizes[tileId] || { columns: 1, rows: 1 }
  }

  function tileHeight(tileId, isEditing) {
    var size = tileSize(tileId)
    if (isEditing) return 94 * size.rows + Math.max(0, size.rows - 1) * 8
    var base = tileId === "weather" ? 140 : tileId === "player" ? 210 : 88
    return base * size.rows + Math.max(0, size.rows - 1) * 10
  }

  function commitLayout(next) {
    if (JSON.stringify(next) === JSON.stringify(widgetLayout)) return
    widgetLayout = next
    scheduleLayoutSave()
  }

  function applyCpu(line) {
    var fields = String(line).trim().split(/\s+/)
    if (fields.length < 6 || fields[0] !== "cpu") return

    var total = 0
    for (var index = 1; index < fields.length; index += 1) {
      total += Math.max(0, Number(fields[index]) || 0)
    }
    var current = {
      total: total,
      idle: (Number(fields[4]) || 0) + (Number(fields[5]) || 0)
    }

    if (previousCpu) {
      var totalDelta = current.total - previousCpu.total
      var idleDelta = current.idle - previousCpu.idle
      if (totalDelta > 0) {
        cpuLoad = Math.max(0, Math.min(1, (totalDelta - idleDelta) / totalDelta))
        cpuText = "CPU  " + Math.round(cpuLoad * 100) + "%"
      }
    }
    previousCpu = current
  }

  function applyGpu(line) {
    var values = String(line).trim().split("|")
    if (values.length >= 2 && isFinite(Number(values[0])) && isFinite(Number(values[1]))) {
      gpuLoad = Math.max(0, Math.min(1, Number(values[0]) / 100))
      gpuText = "GPU  " + Math.round(Number(values[0])) + "%  ·  " + Math.round(Number(values[1])) + "°C"
    } else {
      gpuText = "GPU недоступен"
    }
  }

  function applyTemp(line) {
    var values = String(line).trim().split("|")
    var temperature = Number(values.length > 1 ? values[1] : values[0])
    tempText = isFinite(temperature)
      ? (values.length > 1 ? values[0] : "Система") + "  " + temperature.toFixed(0) + "°C"
      : "Температура недоступна"
  }

  function formatRate(value) {
    var rate = Math.max(0, Number(value) || 0)
    return rate < 1 ? rate.toFixed(2) : rate.toFixed(rate < 10 ? 2 : 1)
  }

  function applyNet(line) {
    var fields = String(line).trim().split(/\s+/)
    if (fields.length < 3) return

    var iface = fields[0]
    var now = Date.now()
    var rx = Number(fields[1])
    var tx = Number(fields[2])
    var speed = Number(fields[3]) || 0
    if (!isFinite(rx) || !isFinite(tx)) return

    if (!previousNet || previousNet.iface !== iface) {
      previousNet = { iface: iface, rx: rx, tx: tx }
      previousNetAt = now
      netLoad = -1
      return
    }

    if (now > previousNetAt) {
      var seconds = (now - previousNetAt) / 1000
      var down = Math.max(0, (rx - previousNet.rx) * 8 / 1e6 / seconds)
      var up = Math.max(0, (tx - previousNet.tx) * 8 / 1e6 / seconds)
      netText = "↓ " + formatRate(down) + "  ↑ " + formatRate(up) + " Mbit/s"
      var capacity = speed > 0 ? speed : 100
      netLoad = Math.max(0, Math.min(1, Math.max(down, up) / capacity))
    }

    previousNet = { iface: iface, rx: rx, tx: tx }
    previousNetAt = now
  }

  function applyPlayer(line) {
    var values = String(line).trim().split("§")
    if (values.length < 7 || values[0] === "") {
      playerTarget = ""
      playerStatus = "Stopped"
      artist = "Ничего не воспроизводится"
      title = "Запустите плеер, чтобы увидеть текущий трек"
      album = ""
      elapsed = "0:00"
      duration = "0:00"
      positionSeconds = 0
      durationSeconds = 0
      progress = 0
      return
    }

    if (playerTarget !== values[0]) {
      playerTarget = values[0]
      playerVolumeAvailable = false
      playerVolumeRefresh.restart()
    }
    playerStatus = values[1]
    artist = values[2] || "Неизвестный исполнитель"
    title = values[3] || "Неизвестный трек"
    album = values[4]

    if (!seeking) {
      positionSeconds = Math.max(0, Number(values[5]) || 0)
      durationSeconds = Math.max(0, Number(values[6]) || 0)
      if (positionSeconds > 1000000) positionSeconds /= 1000000
      if (durationSeconds > 1000000) durationSeconds /= 1000000
      progress = durationSeconds > 0 ? Math.max(0, Math.min(1, positionSeconds / durationSeconds)) : 0
      elapsed = formatTime(positionSeconds)
      duration = formatTime(durationSeconds)
    }
  }

  function loadLayout(raw) {
    if (layoutLoaded) return
    var parsed = null
    if (String(raw).trim() !== "") {
      try {
        parsed = JSON.parse(raw)
      } catch (error) {
        console.warn("widgets: не удалось прочитать раскладку:", error)
      }
    }
    widgetLayout = TileLayout.normalize(parsed)
    layoutLoaded = true
  }

  function scheduleLayoutSave() {
    if (layoutLoaded) layoutSaveTimer.restart()
  }

  function saveLayout() {
    if (!layoutLoaded) return
    layoutFile.setText(JSON.stringify(widgetLayout, null, 2) + "\n")
  }

  function moveTile(tileId, targetSectionId, targetTileId, after) {
    commitLayout(TileLayout.move(widgetLayout, tileId, targetSectionId, targetTileId, after))
  }

  function setLayoutLocked(locked) {
    commitLayout(TileLayout.setLocked(widgetLayout, locked))
  }

  function availableTileIds() {
    return TileLayout.availableTiles(widgetLayout)
  }

  function addTile(tileId, sectionId) {
    commitLayout(TileLayout.addTile(widgetLayout, tileId, sectionId))
  }

  function removeTile(tileId) {
    commitLayout(TileLayout.removeTile(widgetLayout, tileId))
  }

  function addSection(title) {
    commitLayout(TileLayout.addSection(widgetLayout, title))
    sectionDraftTitle = ""
    sectionCreateOpen = false
  }

  function renameSection(sectionId, title) {
    commitLayout(TileLayout.renameSection(widgetLayout, sectionId, title))
  }

  function removeSection(sectionId) {
    commitLayout(TileLayout.removeSection(widgetLayout, sectionId))
  }

  function sectionIndex(sectionId) {
    for (var index = 0; index < widgetLayout.sections.length; index += 1) {
      if (widgetLayout.sections[index].id === sectionId) return index
    }
    return -1
  }

  function moveSection(sectionId, offset) {
    var index = sectionIndex(sectionId)
    var targetIndex = index + offset
    if (index < 0 || targetIndex < 0 || targetIndex >= widgetLayout.sections.length) return
    var targetId = widgetLayout.sections[targetIndex].id
    commitLayout(TileLayout.moveSection(widgetLayout, sectionId, targetId, offset > 0))
  }

  function moveSectionTo(sectionId, targetSectionId, after) {
    commitLayout(TileLayout.moveSection(widgetLayout, sectionId, targetSectionId, after))
  }

  function resizeTile(tileId, columnDelta, rowDelta) {
    var size = tileSize(tileId)
    commitLayout(TileLayout.resizeTile(widgetLayout, tileId, size.columns + columnDelta, size.rows + rowDelta))
  }

  function resetTileSize(tileId) {
    commitLayout(TileLayout.resetTileSize(widgetLayout, tileId))
  }

  function resetSizes() {
    commitLayout(TileLayout.resetSizes(widgetLayout))
  }

  function setAppearance(patch) {
    commitLayout(TileLayout.updateAppearance(widgetLayout, patch))
  }

  function setWallpaper(theme, id) {
    var wallpapers = {
      light: widgetLayout.appearance.wallpapers.light,
      dark: widgetLayout.appearance.wallpapers.dark
    }
    wallpapers[theme] = id
    setAppearance({ wallpapers: wallpapers })
  }

  function setWallpaperOpacity(theme, opacity) {
    var values = {
      light: widgetLayout.appearance.wallpaperOpacity.light,
      dark: widgetLayout.appearance.wallpaperOpacity.dark
    }
    values[theme] = opacity
    setAppearance({ wallpaperOpacity: values })
  }

  function setTheme(mode) {
    if (TileLayout.THEME_IDS.indexOf(mode) === -1 || mode === widgetLayout.theme) return
    var next = TileLayout.normalize(widgetLayout)
    next.theme = mode
    commitLayout(TileLayout.normalize(next))
  }

  function toggleTheme() {
    setTheme(isDark ? "light" : "dark")
  }

  function resetLayout() {
    commitLayout(TileLayout.resetLayout())
  }

  Process {
    id: weather
    command: [Quickshell.env("HOME") + "/.local/share/omarchy/weather/weather-backend", "--line"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.applyWeather(line) }
    }
  }

  Process {
    id: cpu
    command: ["sh", root.pluginDir + "/metrics-backend", "cpu"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.applyCpu(line) }
    }
  }

  Process {
    id: gpu
    command: ["sh", root.pluginDir + "/metrics-backend", "gpu"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.applyGpu(line) }
    }
  }

  Process {
    id: temp
    command: ["sh", root.pluginDir + "/metrics-backend", "temp"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.applyTemp(line) }
    }
  }

  Process {
    id: net
    command: ["sh", root.pluginDir + "/metrics-backend", "net"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.applyNet(line) }
    }
  }

  Process {
    id: player
    command: ["sh", root.pluginDir + "/player-control.sh", "metadata"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.applyPlayer(line) }
    }
  }

  Process {
    id: playerVolumeProcess
    command: ["sh", root.pluginDir + "/player-control.sh", "volume-get"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.applyPlayerVolume(line, root.volumeReadRevision) }
    }
    onExited: root.finishPlayerVolumeRead()
  }

  Process {
    id: volumeWriteProcess
    command: ["true"]
    onExited: function(exitCode) { root.finishPlayerVolumeWrite(exitCode) }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: {
      cpu.running = true
      net.running = true
      player.running = true
      root.requestPlayerVolume()
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: {
      gpu.running = true
      temp.running = true
    }
  }

  Timer {
    interval: 900000
    running: true
    repeat: true
    onTriggered: weather.running = true
  }

  Timer {
    id: playerPoll
    interval: 350
    repeat: false
    onTriggered: player.running = true
  }

  Timer {
    id: playerVolumeRefresh
    interval: 180
    repeat: false
    onTriggered: root.requestPlayerVolume()
  }

  FileView {
    id: layoutFile
    path: root.layoutPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadLayout(text())
    onLoadFailed: root.loadLayout("")
    onSaveFailed: function(error) { console.warn("widgets: не удалось сохранить раскладку:", error) }
  }

  Process {
    id: ensureLayoutDirectory
    command: ["mkdir", "-p", root.layoutDirectory]
    onExited: layoutFile.reload()
  }

  Timer {
    id: layoutSaveTimer
    interval: 220
    repeat: false
    onTriggered: root.saveLayout()
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      anchors {
        top: true
        right: true
      }
      margins {
        top: 52
        right: 30
      }
      implicitWidth: 480
      implicitHeight: Math.max(320, Math.min(contentColumn.implicitHeight + 36, modelData.height - 76))
      color: "transparent"
      WlrLayershell.namespace: "omarchy-widgets"
      // Keep the dashboard above the wallpaper but below application windows.
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
      exclusionMode: ExclusionMode.Ignore

      Image {
        anchors.fill: parent
        source: root.wallpaperUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        opacity: root.wallpaperOpacity
        visible: root.wallpaperOpacity > 0
      }

      Rectangle {
        anchors.fill: parent
        radius: 24
        color: root.panelSurface
        border.width: 1
        border.color: root.panelBorder
      }

      Flickable {
        id: viewport
        anchors.fill: parent
        anchors.margins: 18
        clip: true
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        interactive: !root.editing
          || (contentColumn.implicitHeight > viewport.height && !root.draggingItems)
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
          id: contentColumn
          width: viewport.width
          spacing: 12

          RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            spacing: 9

            Rectangle {
              width: 38
              height: 38
              radius: 14
              color: root.accentSurface
              border.width: 1
              border.color: root.surfaceBorder
              Layout.alignment: Qt.AlignVCenter

              Text {
                anchors.centerIn: parent
                text: "⌂"
                color: root.accentColor
                font.family: root.uiFont
                font.pixelSize: 21
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2

              Text {
                text: "Обзор рабочего стола"
                color: root.primaryText
                font.family: root.uiFont
                font.pixelSize: 14
                font.bold: true
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Text {
                text: "Погода · система · медиа"
                color: root.secondaryText
                font.family: root.uiFont
                font.pixelSize: 11
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
            }

            Rectangle {
              width: 92
              height: 36
              radius: 13
              color: themeMouse.containsMouse ? root.accentHover : root.raisedSurface
              border.width: 1
              border.color: root.surfaceBorder
              Layout.alignment: Qt.AlignVCenter

              Row {
                anchors.centerIn: parent
                spacing: 5

                Text {
                  text: root.isDark ? "☼" : "☾"
                  color: root.accentColor
                  font.family: root.uiFont
                  font.pixelSize: 14
                }

                Text {
                  text: root.isDark ? "Светлая" : "Тёмная"
                  color: root.primaryText
                  font.family: root.uiFont
                  font.pixelSize: 10
                  font.bold: true
                }
              }

              MouseArea {
                id: themeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleTheme()
              }
            }

            Rectangle {
              width: 88
              height: 36
              radius: 13
              color: root.editing ? root.accentColor : (editMouse.containsMouse ? root.accentHover : root.raisedSurface)
              border.width: 1
              border.color: root.editing ? root.accentColor : root.surfaceBorder
              Layout.alignment: Qt.AlignVCenter

              Text {
                anchors.centerIn: parent
                text: root.editing ? "Готово" : "Настроить"
                color: root.editing ? "#FFFFFFFF" : root.primaryText
                font.family: root.uiFont
                font.pixelSize: 11
                font.bold: true
              }

              MouseArea {
                id: editMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (!root.editing) root.editorTab = "layout"
                  root.editing = !root.editing
                }
              }
            }
          }

          RowLayout {
            visible: root.editing
            Layout.fillWidth: true
            Layout.preferredHeight: 31
            spacing: 6

            Repeater {
              model: [
                { id: "layout", label: "Раскладка" },
                { id: "appearance", label: "Оформление" }
              ]

              delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 31
                radius: 11
                color: root.editorTab === modelData.id ? root.accentColor : root.raisedSurface
                border.width: 1
                border.color: root.editorTab === modelData.id ? root.accentColor : root.surfaceBorder

                Text {
                  anchors.centerIn: parent
                  text: modelData.label
                  color: root.editorTab === modelData.id ? "#FFFFFFFF" : root.primaryText
                  font.family: root.uiFont
                  font.pixelSize: 10
                  font.bold: root.editorTab === modelData.id
                }

                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.editorTab = modelData.id
                }
              }
            }
          }

          ColumnLayout {
            visible: root.editing && root.editorTab === "layout"
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
              Layout.fillWidth: true
              Layout.preferredHeight: 28
              spacing: 5

              Text {
                text: "ТЕМА"
                color: root.secondaryText
                font.family: root.uiFont
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 0.6
              }

              Repeater {
                model: root.themeOptions

                delegate: Rectangle {
                  required property var modelData
                  Layout.fillWidth: true
                  Layout.preferredHeight: 28
                  radius: 10
                  color: root.widgetLayout.theme === modelData.mode ? root.accentColor : root.raisedSurface
                  border.width: 1
                  border.color: root.widgetLayout.theme === modelData.mode ? root.accentColor : root.surfaceBorder

                  Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: root.widgetLayout.theme === modelData.mode ? "#FFFFFFFF" : root.primaryText
                    font.family: root.uiFont
                    font.pixelSize: 10
                    font.bold: root.widgetLayout.theme === modelData.mode
                  }

                  MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setTheme(modelData.mode)
                  }
                }
              }
            }

            GridLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: width
              Layout.preferredHeight: 64
              columns: 2
              rowSpacing: 6
              columnSpacing: 6

              Repeater {
                model: [
                  { id: "lock", label: root.widgetLayout.locked ? "Разблокировать" : "Заблокировать" },
                  { id: "sizes", label: "Размеры по умолчанию" },
                  { id: "reset", label: "Сбросить раскладку" },
                  { id: "section", label: "+ Новый блок" }
                ]

                delegate: Rectangle {
                  required property var modelData
                  Layout.fillWidth: true
                  Layout.preferredHeight: 29
                  height: 29
                  radius: 10
                  color: modelData.id === "lock" && root.widgetLayout.locked
                    ? root.accentSurface : actionMouse.containsMouse ? root.accentHover : root.raisedSurface
                  border.width: 1
                  border.color: modelData.id === "lock" && root.widgetLayout.locked
                    ? root.accentColor : root.surfaceBorder

                  Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: modelData.id === "lock" && root.widgetLayout.locked
                      ? root.accentColor : root.primaryText
                    font.family: root.uiFont
                    font.pixelSize: 10
                    font.bold: true
                    elide: Text.ElideRight
                    width: parent.width - 10
                  }

                  MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.id === "lock"
                      ? (root.widgetLayout.locked ? "Разблокировать перемещения" : "Заблокировать перемещения")
                      : modelData.label
                    onClicked: {
                      if (modelData.id === "lock") root.setLayoutLocked(!root.widgetLayout.locked)
                      else if (modelData.id === "sizes") root.resetSizes()
                      else if (modelData.id === "reset") root.resetLayout()
                      else root.addSection("Новый блок")
                    }
                  }
                }
              }
            }

            Text {
              text: "Тяните блоки за ручку, плитки — за карточку. Замок блокирует перемещение; двойной щелчок сбрасывает размер."
              color: root.secondaryText
              font.family: root.uiFont
              font.pixelSize: 9
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }
          }

          ColumnLayout {
            visible: root.editing && root.editorTab === "appearance"
            Layout.fillWidth: true
            spacing: 9

            Text {
              text: "ФОНЫ ПО ТЕМАМ"
              color: root.secondaryText
              font.family: root.uiFont
              font.pixelSize: 9
              font.bold: true
              font.letterSpacing: 0.7
            }

            Repeater {
              model: [
                { id: "light", label: "Светлая тема" },
                { id: "dark", label: "Тёмная тема" }
              ]

              delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 4

                Text {
                  text: modelData.label
                  color: root.primaryText
                  font.family: root.uiFont
                  font.pixelSize: 10
                  font.bold: true
                }

                Flow {
                  Layout.fillWidth: true
                  Layout.preferredWidth: width
                  Layout.preferredHeight: 69
                  spacing: 8

                  Repeater {
                    model: root.wallpaperOptions(modelData.id)

                    delegate: Rectangle {
                      required property var modelData
                      width: Math.floor((parent.width - 8) / 2)
                      height: 69
                      radius: 12
                      clip: true
                      color: root.raisedSurface
                      border.width: root.widgetLayout.appearance.wallpapers[modelData.id.indexOf("light-") === 0 ? "light" : "dark"] === modelData.id ? 2 : 1
                      border.color: root.widgetLayout.appearance.wallpapers[modelData.id.indexOf("light-") === 0 ? "light" : "dark"] === modelData.id
                        ? root.accentColor : root.surfaceBorder

                      Image {
                        anchors.fill: parent
                        source: Qt.resolvedUrl("backgrounds/" + modelData.id + ".svg")
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                      }

                      Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 23
                        color: root.isDark ? "#C3111514" : "#DDF1F2EF"

                        Text {
                          anchors.fill: parent
                          anchors.leftMargin: 7
                          anchors.rightMargin: 5
                          verticalAlignment: Text.AlignVCenter
                          text: modelData.label
                          color: root.primaryText
                          font.family: root.uiFont
                          font.pixelSize: 9
                          font.bold: true
                          elide: Text.ElideRight
                        }
                      }

                      MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        Accessible.name: "Фон: " + modelData.label
                        onClicked: root.setWallpaper(modelData.id.indexOf("light-") === 0 ? "light" : "dark", modelData.id)
                      }
                    }
                  }
                }

                SettingsSlider {
                  Layout.fillWidth: true
                  label: "Прозрачность фона"
                  value: root.widgetLayout.appearance.wallpaperOpacity[modelData.id]
                  minimum: 0
                  maximum: 1
                  accent: root.accentColor
                  track: root.trackColor
                  textColor: root.primaryText
                  mutedColor: root.secondaryText
                  onValueEdited: function(value) { root.setWallpaperOpacity(modelData.id, value) }
                }
              }
            }

            SettingsSlider {
              Layout.fillWidth: true
              label: "Непрозрачность общей подложки"
              value: root.widgetLayout.appearance.panelOpacity
              minimum: 0.65
              maximum: 1
              accent: root.accentColor
              track: root.trackColor
              textColor: root.primaryText
              mutedColor: root.secondaryText
              onValueEdited: function(value) { root.setAppearance({ panelOpacity: value }) }
            }

            SettingsSlider {
              Layout.fillWidth: true
              label: "Непрозрачность плиток"
              value: root.widgetLayout.appearance.tileOpacity
              minimum: 0.65
              maximum: 1
              accent: root.accentColor
              track: root.trackColor
              textColor: root.primaryText
              mutedColor: root.secondaryText
              onValueEdited: function(value) { root.setAppearance({ tileOpacity: value }) }
            }

            Text {
              text: "ЗНАЧКИ ПОГОДЫ"
              color: root.secondaryText
              font.family: root.uiFont
              font.pixelSize: 9
              font.bold: true
              font.letterSpacing: 0.7
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 6

              Repeater {
                model: root.weatherIconOptions

                delegate: Rectangle {
                  required property var modelData
                  Layout.fillWidth: true
                  Layout.preferredHeight: 34
                  radius: 11
                  color: root.widgetLayout.appearance.weatherIconSet === modelData.id
                    ? root.accentSurface : root.raisedSurface
                  border.width: 1
                  border.color: root.widgetLayout.appearance.weatherIconSet === modelData.id
                    ? root.accentColor : root.surfaceBorder

                  Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                      text: modelData.sample
                      font.family: modelData.id === "color" ? "Noto Color Emoji" : root.uiFont
                      font.pixelSize: 15
                    }

                    Text {
                      text: modelData.label
                      color: root.widgetLayout.appearance.weatherIconSet === modelData.id
                        ? root.accentColor : root.primaryText
                      font.family: root.uiFont
                      font.pixelSize: 9
                      font.bold: true
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    Accessible.name: "Набор погодных значков: " + modelData.label
                    onClicked: root.setAppearance({ weatherIconSet: modelData.id })
                  }
                }
              }
            }
          }

          ColumnLayout {
            visible: !root.editing || root.editorTab === "layout"
            Layout.fillWidth: true
            spacing: 10

            Text {
            visible: root.editing && root.editorTab === "layout"
            Layout.fillWidth: true
            Layout.preferredHeight: 15
            text: "РАЗДЕЛЫ И ПЛИТКИ"
            color: root.secondaryText
            font.family: root.uiFont
            font.pixelSize: 9
            font.bold: true
            font.letterSpacing: 0.7
            }

            Repeater {
              model: root.widgetLayout.sections

              delegate: WidgetSection {
                required property var modelData
                sectionId: modelData.id
                title: modelData.title
                tileIds: modelData.tiles
                availableTiles: root.availableTileIds()
                dashboard: root
                dragLayer: dragOverlay
                editing: root.editing && root.editorTab === "layout"
                Layout.fillWidth: true
              }
            }
          }
        }
      }

      Rectangle {
        width: 3
        height: Math.max(34, viewport.height * viewport.height / Math.max(1, viewport.contentHeight))
        x: viewport.x + viewport.width - width
        y: viewport.y + (viewport.contentY / Math.max(1, viewport.contentHeight - viewport.height))
          * (viewport.height - height)
        radius: 2
        color: root.accentColor
        visible: viewport.contentHeight > viewport.height
        opacity: root.editing ? 0.55 : 0.72
      }

      Item {
        id: dragOverlay
        x: viewport.x
        y: viewport.y
        width: viewport.width
        height: viewport.height
        z: 50
        clip: false
        visible: root.editing
      }
    }
  }

  Component.onCompleted: ensureLayoutDirectory.running = true

  Process {
    id: control
    command: ["true"]
  }
}
