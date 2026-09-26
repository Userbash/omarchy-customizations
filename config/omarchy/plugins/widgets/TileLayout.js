var VERSION = 3
var SECTION_IDS = ["weather", "system", "media"]
var TILE_IDS = ["weather", "cpu", "gpu", "temperature", "network", "player"]
var THEME_IDS = ["auto", "light", "dark"]
var WEATHER_ICON_SETS = ["minimal", "color"]
var LIGHT_WALLPAPERS = ["light-sakura", "light-evening"]
var DARK_WALLPAPERS = ["dark-orbit", "dark-forest"]
var MAX_SECTIONS = 13

var DEFAULT_SECTIONS = [
  { id: "weather", title: "Погода", tiles: ["weather"] },
  { id: "system", title: "Система", tiles: ["cpu", "gpu", "temperature", "network"] },
  { id: "media", title: "Медиа", tiles: ["player"] }
]

var DEFAULT_TILE_SIZES = {
  weather: { columns: 2, rows: 1 },
  cpu: { columns: 1, rows: 1 },
  gpu: { columns: 1, rows: 1 },
  temperature: { columns: 1, rows: 1 },
  network: { columns: 1, rows: 1 },
  player: { columns: 2, rows: 1 }
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function hasValue(values, value) {
  return values.indexOf(value) !== -1
}

function clamp(value, minimum, maximum, fallback) {
  var number = Number(value)
  if (!isFinite(number)) return fallback
  return Math.max(minimum, Math.min(maximum, number))
}

function safeOpacity(value, minimum, fallback) {
  return Math.round(clamp(value, minimum, 1, fallback) * 100) / 100
}

function safeWallpaper(theme, value, fallback) {
  var available = theme === "light" ? LIGHT_WALLPAPERS : DARK_WALLPAPERS
  return hasValue(available, value) ? value : fallback
}

function defaultAppearance() {
  return {
    panelOpacity: 0.72,
    tileOpacity: 0.92,
    wallpaperOpacity: { light: 0.92, dark: 0.92 },
    wallpapers: { light: "light-sakura", dark: "dark-orbit" },
    weatherIconSet: "minimal"
  }
}

function cloneSections(sections) {
  var cloned = []
  for (var index = 0; index < sections.length; index += 1) {
    cloned.push({
      id: sections[index].id,
      title: sections[index].title,
      tiles: sections[index].tiles.slice()
    })
  }
  return cloned
}

function defaultLayout() {
  var sizes = {}
  for (var index = 0; index < TILE_IDS.length; index += 1) {
    var id = TILE_IDS[index]
    sizes[id] = { columns: DEFAULT_TILE_SIZES[id].columns, rows: DEFAULT_TILE_SIZES[id].rows }
  }
  return {
    version: VERSION,
    theme: "auto",
    locked: false,
    sections: cloneSections(DEFAULT_SECTIONS),
    tileSizes: sizes,
    appearance: defaultAppearance()
  }
}

function defaultTitle(sectionId) {
  if (sectionId === "weather") return "Погода"
  if (sectionId === "system") return "Система"
  if (sectionId === "media") return "Медиа"
  return "Новый блок"
}

function normalizeSectionId(value, index) {
  var id = String(value || "").trim()
  if (!/^[a-z][a-z0-9_-]{0,31}$/.test(id)) return "section-" + (index + 1)
  return id
}

function normalizeTitle(value, fallback) {
  var title = String(value === undefined || value === null ? "" : value).trim()
  if (title === "") return fallback
  return title.slice(0, 32)
}

function normalizeSize(tileId, raw) {
  var defaults = DEFAULT_TILE_SIZES[tileId]
  var value = isObject(raw) ? raw : {}
  var columns = Math.round(clamp(value.columns, 1, 2, defaults.columns))
  var rows = Math.round(clamp(value.rows, 1, 2, defaults.rows))
  if (tileId === "player") columns = 2
  return { columns: columns, rows: rows }
}

function normalizeAppearance(raw) {
  var fallback = defaultAppearance()
  var value = isObject(raw) ? raw : {}
  var wallpaperOpacity = isObject(value.wallpaperOpacity) ? value.wallpaperOpacity : {}
  var wallpapers = isObject(value.wallpapers) ? value.wallpapers : {}

  return {
    panelOpacity: safeOpacity(value.panelOpacity, 0.65, fallback.panelOpacity),
    tileOpacity: safeOpacity(value.tileOpacity, 0.65, fallback.tileOpacity),
    wallpaperOpacity: {
      light: Math.round(clamp(wallpaperOpacity.light, 0, 1, fallback.wallpaperOpacity.light) * 100) / 100,
      dark: Math.round(clamp(wallpaperOpacity.dark, 0, 1, fallback.wallpaperOpacity.dark) * 100) / 100
    },
    wallpapers: {
      light: safeWallpaper("light", wallpapers.light, fallback.wallpapers.light),
      dark: safeWallpaper("dark", wallpapers.dark, fallback.wallpapers.dark)
    },
    weatherIconSet: hasValue(WEATHER_ICON_SETS, value.weatherIconSet)
      ? value.weatherIconSet
      : fallback.weatherIconSet
  }
}

function normalizeV1(raw) {
  var normalized = defaultLayout()
  normalized.theme = hasValue(THEME_IDS, raw.theme) ? raw.theme : "auto"
  var source = isObject(raw.sections) ? raw.sections : {}
  var seen = {}

  for (var sectionIndex = 0; sectionIndex < SECTION_IDS.length; sectionIndex += 1) {
    var sectionId = SECTION_IDS[sectionIndex]
    var target = normalized.sections[sectionIndex]
    var incoming = Array.isArray(source[sectionId]) ? source[sectionId] : []
    target.tiles = []
    for (var tileIndex = 0; tileIndex < incoming.length; tileIndex += 1) {
      var tileId = incoming[tileIndex]
      if (!hasValue(TILE_IDS, tileId) || seen[tileId]) continue
      target.tiles.push(tileId)
      seen[tileId] = true
    }
  }

  for (var defaultSectionIndex = 0; defaultSectionIndex < DEFAULT_SECTIONS.length; defaultSectionIndex += 1) {
    var defaultSection = DEFAULT_SECTIONS[defaultSectionIndex]
    var targetSection = normalized.sections[defaultSectionIndex]
    for (var defaultTileIndex = 0; defaultTileIndex < defaultSection.tiles.length; defaultTileIndex += 1) {
      var defaultTileId = defaultSection.tiles[defaultTileIndex]
      if (!seen[defaultTileId]) {
        targetSection.tiles.push(defaultTileId)
        seen[defaultTileId] = true
      }
    }
  }

  return ensureMediaPlayer(normalized)
}

function ensureMediaPlayer(layout) {
  var mediaIndex = findSection(layout, "media")
  if (mediaIndex === -1) {
    if (layout.sections.length >= MAX_SECTIONS) layout.sections.pop()
    layout.sections.push({ id: "media", title: defaultTitle("media"), tiles: [] })
    mediaIndex = layout.sections.length - 1
  }

  for (var sectionIndex = 0; sectionIndex < layout.sections.length; sectionIndex += 1) {
    var tiles = layout.sections[sectionIndex].tiles
    for (var tileIndex = tiles.length - 1; tileIndex >= 0; tileIndex -= 1) {
      if (tiles[tileIndex] === "player" && sectionIndex !== mediaIndex) tiles.splice(tileIndex, 1)
    }
  }

  var mediaTiles = layout.sections[mediaIndex].tiles
  if (mediaTiles.indexOf("player") === -1) mediaTiles.push("player")
  return layout
}

function normalize(raw) {
  var fallback = defaultLayout()
  if (!isObject(raw)) return fallback
  if (raw.version === 1) return normalizeV1(raw)
  if (raw.version !== 2 && raw.version !== VERSION) return fallback

  var normalized = defaultLayout()
  normalized.theme = hasValue(THEME_IDS, raw.theme) ? raw.theme : "auto"
  normalized.locked = raw.locked === true
  normalized.sections = []
  normalized.appearance = normalizeAppearance(raw.appearance)

  var seenSectionIds = {}
  var seenTiles = {}
  var sourceSections = Array.isArray(raw.sections) ? raw.sections : []
  var sectionCount = Math.min(sourceSections.length, MAX_SECTIONS)
  for (var sectionIndex = 0; sectionIndex < sectionCount; sectionIndex += 1) {
    var incomingSection = sourceSections[sectionIndex]
    if (!isObject(incomingSection)) continue
    var sectionId = normalizeSectionId(incomingSection.id, sectionIndex)
    var baseSectionId = sectionId
    var suffix = 2
    while (seenSectionIds[sectionId]) {
      sectionId = baseSectionId.slice(0, 26) + "-" + suffix
      suffix += 1
    }
    seenSectionIds[sectionId] = true

    var section = {
      id: sectionId,
      title: normalizeTitle(incomingSection.title, defaultTitle(sectionId)),
      tiles: []
    }
    var incomingTiles = Array.isArray(incomingSection.tiles) ? incomingSection.tiles : []
    for (var tileIndex = 0; tileIndex < incomingTiles.length; tileIndex += 1) {
      var tileId = incomingTiles[tileIndex]
      if (!hasValue(TILE_IDS, tileId) || seenTiles[tileId]) continue
      if (tileId === "player" && sectionId !== "media") continue
      section.tiles.push(tileId)
      seenTiles[tileId] = true
    }
    normalized.sections.push(section)
  }

  var sourceSizes = isObject(raw.tileSizes) ? raw.tileSizes : {}
  normalized.tileSizes = {}
  for (var tileSizeIndex = 0; tileSizeIndex < TILE_IDS.length; tileSizeIndex += 1) {
    var sizedTileId = TILE_IDS[tileSizeIndex]
    normalized.tileSizes[sizedTileId] = normalizeSize(sizedTileId, sourceSizes[sizedTileId])
  }

  return ensureMediaPlayer(normalized)
}

function findSection(layout, sectionId) {
  for (var index = 0; index < layout.sections.length; index += 1) {
    if (layout.sections[index].id === sectionId) return index
  }
  return -1
}

function findTile(layout, tileId) {
  for (var sectionIndex = 0; sectionIndex < layout.sections.length; sectionIndex += 1) {
    var tileIndex = layout.sections[sectionIndex].tiles.indexOf(tileId)
    if (tileIndex !== -1) return { sectionIndex: sectionIndex, tileIndex: tileIndex }
  }
  return null
}

function move(layout, tileId, targetSectionId, targetTileId, after) {
  var next = normalize(layout)
  if (next.locked) return next
  if (!hasValue(TILE_IDS, tileId) || findSection(next, targetSectionId) === -1) return next
  if (tileId === "player" && targetSectionId !== "media") return next
  if (targetTileId && (!hasValue(TILE_IDS, targetTileId) || targetTileId === tileId)) return next

  var source = findTile(next, tileId)
  if (!source) return next
  next.sections[source.sectionIndex].tiles.splice(source.tileIndex, 1)
  var target = next.sections[findSection(next, targetSectionId)].tiles
  var insertIndex = target.length
  if (targetTileId) {
    insertIndex = target.indexOf(targetTileId)
    if (insertIndex === -1) return normalize(layout)
    if (after) insertIndex += 1
  }
  target.splice(insertIndex, 0, tileId)
  return next
}

function availableTiles(layout) {
  var normalized = normalize(layout)
  var placed = {}
  for (var sectionIndex = 0; sectionIndex < normalized.sections.length; sectionIndex += 1) {
    var tiles = normalized.sections[sectionIndex].tiles
    for (var tileIndex = 0; tileIndex < tiles.length; tileIndex += 1) placed[tiles[tileIndex]] = true
  }
  var available = []
  for (var index = 0; index < TILE_IDS.length; index += 1) {
    if (!placed[TILE_IDS[index]]) available.push(TILE_IDS[index])
  }
  return available
}

function addTile(layout, tileId, sectionId) {
  var next = normalize(layout)
  if (!hasValue(TILE_IDS, tileId) || findSection(next, sectionId) === -1) return next
  if (tileId === "player" && sectionId !== "media") return next
  if (findTile(next, tileId)) return next
  next.sections[findSection(next, sectionId)].tiles.push(tileId)
  return next
}

function removeTile(layout, tileId) {
  var next = normalize(layout)
  if (tileId === "player") return next
  if (!hasValue(TILE_IDS, tileId)) return next
  var found = findTile(next, tileId)
  if (found) next.sections[found.sectionIndex].tiles.splice(found.tileIndex, 1)
  return next
}

function addSection(layout, title) {
  var next = normalize(layout)
  if (next.sections.length >= MAX_SECTIONS) return next
  var serial = 1
  var sectionId = "section-" + serial
  while (findSection(next, sectionId) !== -1) {
    serial += 1
    sectionId = "section-" + serial
  }
  next.sections.push({ id: sectionId, title: normalizeTitle(title, "Новый блок"), tiles: [] })
  return next
}

function renameSection(layout, sectionId, title) {
  var next = normalize(layout)
  var index = findSection(next, sectionId)
  if (index === -1) return next
  next.sections[index].title = normalizeTitle(title, "Новый блок")
  return next
}

function removeSection(layout, sectionId) {
  var next = normalize(layout)
  if (sectionId === "media") return next
  var index = findSection(next, sectionId)
  if (index !== -1) next.sections.splice(index, 1)
  return next
}

function moveSection(layout, sectionId, targetSectionId, after) {
  var next = normalize(layout)
  if (next.locked) return next
  var sourceIndex = findSection(next, sectionId)
  var targetIndex = findSection(next, targetSectionId)
  if (sourceIndex === -1 || targetIndex === -1 || sourceIndex === targetIndex) return next
  var section = next.sections.splice(sourceIndex, 1)[0]
  if (sourceIndex < targetIndex) targetIndex -= 1
  if (after) targetIndex += 1
  next.sections.splice(targetIndex, 0, section)
  return next
}

function resizeTile(layout, tileId, columns, rows) {
  var next = normalize(layout)
  if (!hasValue(TILE_IDS, tileId)) return next
  var size = normalizeSize(tileId, { columns: columns, rows: rows })
  next.tileSizes[tileId] = size
  return next
}

function resetTileSize(layout, tileId) {
  var next = normalize(layout)
  if (!hasValue(TILE_IDS, tileId)) return next
  var defaults = DEFAULT_TILE_SIZES[tileId]
  next.tileSizes[tileId] = { columns: defaults.columns, rows: defaults.rows }
  return next
}

function resetSizes(layout) {
  var next = normalize(layout)
  var defaults = defaultLayout().tileSizes
  next.tileSizes = defaults
  return next
}

function updateAppearance(layout, patch) {
  var next = normalize(layout)
  if (!isObject(patch)) return next
  var appearance = next.appearance
  if (patch.panelOpacity !== undefined) appearance.panelOpacity = patch.panelOpacity
  if (patch.tileOpacity !== undefined) appearance.tileOpacity = patch.tileOpacity
  if (isObject(patch.wallpaperOpacity)) {
    if (patch.wallpaperOpacity.light !== undefined) appearance.wallpaperOpacity.light = patch.wallpaperOpacity.light
    if (patch.wallpaperOpacity.dark !== undefined) appearance.wallpaperOpacity.dark = patch.wallpaperOpacity.dark
  }
  if (isObject(patch.wallpapers)) {
    if (hasValue(LIGHT_WALLPAPERS, patch.wallpapers.light)) appearance.wallpapers.light = patch.wallpapers.light
    if (hasValue(DARK_WALLPAPERS, patch.wallpapers.dark)) appearance.wallpapers.dark = patch.wallpapers.dark
  }
  if (hasValue(WEATHER_ICON_SETS, patch.weatherIconSet)) appearance.weatherIconSet = patch.weatherIconSet
  next.appearance = normalizeAppearance(appearance)
  return next
}

function setLocked(layout, locked) {
  var next = normalize(layout)
  next.locked = locked === true
  return next
}

function resetLayout() {
  return defaultLayout()
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    VERSION: VERSION,
    SECTION_IDS: SECTION_IDS,
    TILE_IDS: TILE_IDS,
    THEME_IDS: THEME_IDS,
    WEATHER_ICON_SETS: WEATHER_ICON_SETS,
    LIGHT_WALLPAPERS: LIGHT_WALLPAPERS,
    DARK_WALLPAPERS: DARK_WALLPAPERS,
    MAX_SECTIONS: MAX_SECTIONS,
    defaultLayout: defaultLayout,
    resetLayout: resetLayout,
    normalize: normalize,
    move: move,
    availableTiles: availableTiles,
    addTile: addTile,
    removeTile: removeTile,
    addSection: addSection,
    renameSection: renameSection,
    removeSection: removeSection,
    moveSection: moveSection,
    setLocked: setLocked,
    resizeTile: resizeTile,
    resetTileSize: resetTileSize,
    resetSizes: resetSizes,
    updateAppearance: updateAppearance
  }
}
