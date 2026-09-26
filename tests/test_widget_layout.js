const assert = require("node:assert/strict")
const TileLayout = require("../config/omarchy/plugins/widgets/TileLayout.js")

function section(layout, id) {
  return layout.sections.find((entry) => entry.id === id)
}

function tileIds(layout, id) {
  const value = section(layout, id)
  return value ? value.tiles : []
}

const defaults = TileLayout.defaultLayout()
assert.equal(defaults.version, 2)
assert.equal(defaults.theme, "auto")
assert.deepEqual(defaults.sections.map((entry) => entry.id), ["weather", "system", "media"])
assert.deepEqual(tileIds(defaults, "weather"), ["weather"])
assert.deepEqual(tileIds(defaults, "system"), ["cpu", "gpu", "temperature", "network"])
assert.deepEqual(tileIds(defaults, "media"), ["player"])
assert.deepEqual(defaults.tileSizes.player, { columns: 2, rows: 1 })
assert.equal(defaults.appearance.weatherIconSet, "minimal")
assert.ok(defaults.appearance.panelOpacity > 0 && defaults.appearance.panelOpacity <= 1)

const migrated = TileLayout.normalize({
  version: 1,
  theme: "dark",
  sections: {
    weather: ["cpu", "weather", "cpu", "unknown"],
    system: ["player", "gpu"],
    media: []
  }
})
assert.equal(migrated.version, 2)
assert.equal(migrated.theme, "dark")
assert.deepEqual(tileIds(migrated, "weather"), ["cpu", "weather"])
assert.deepEqual(tileIds(migrated, "system"), ["player", "gpu", "temperature", "network"])
assert.deepEqual(tileIds(migrated, "media"), [])
assert.deepEqual(TileLayout.normalize({ version: 99 }), defaults)
assert.deepEqual(TileLayout.normalize("broken"), defaults)

const roundTrip = TileLayout.normalize(JSON.parse(JSON.stringify(defaults)))
assert.deepEqual(roundTrip, defaults)

const reordered = TileLayout.move(defaults, "network", "system", "cpu", false)
assert.deepEqual(tileIds(reordered, "system"), ["network", "cpu", "gpu", "temperature"])

const movedAcross = TileLayout.move(defaults, "weather", "system", "gpu", true)
assert.deepEqual(tileIds(movedAcross, "weather"), [])
assert.deepEqual(tileIds(movedAcross, "system"), ["cpu", "gpu", "weather", "temperature", "network"])

const movedToEmpty = TileLayout.move(defaults, "player", "weather", "", true)
assert.deepEqual(tileIds(movedToEmpty, "media"), [])
assert.deepEqual(tileIds(movedToEmpty, "weather"), ["weather", "player"])

const movedWithin = TileLayout.move(defaults, "cpu", "system", "network", true)
assert.deepEqual(tileIds(movedWithin, "system"), ["gpu", "temperature", "network", "cpu"])
assert.deepEqual(TileLayout.move(defaults, "cpu", "system", "cpu", true), defaults)
assert.deepEqual(TileLayout.move(defaults, "missing", "system", "gpu", false), defaults)
assert.deepEqual(TileLayout.move(defaults, "cpu", "unknown", "gpu", false), defaults)
assert.deepEqual(TileLayout.move(defaults, "cpu", "system", "missing", false), defaults)

const sectionAdded = TileLayout.addSection(defaults, "Кабинет")
assert.ok(section(sectionAdded, "section-1"))
assert.equal(section(sectionAdded, "section-1").title, "Кабинет")
const renamed = TileLayout.renameSection(sectionAdded, "section-1", "  Рабочая зона  ")
assert.equal(section(renamed, "section-1").title, "Рабочая зона")
const sectionMoved = TileLayout.moveSection(renamed, "section-1", "weather", false)
assert.deepEqual(sectionMoved.sections.map((entry) => entry.id), ["section-1", "weather", "system", "media"])

const mediaSectionRemoved = TileLayout.removeSection(defaults, "media")
assert.equal(section(mediaSectionRemoved, "media"), undefined)
assert.deepEqual(TileLayout.availableTiles(mediaSectionRemoved), ["player"])
const playerAdded = TileLayout.addTile(mediaSectionRemoved, "player", "system")
assert.deepEqual(tileIds(playerAdded, "system").slice(-1), ["player"])
assert.deepEqual(TileLayout.availableTiles(playerAdded), [])
assert.deepEqual(TileLayout.addTile(playerAdded, "player", "weather"), playerAdded)
const playerRemoved = TileLayout.removeTile(playerAdded, "player")
assert.deepEqual(TileLayout.availableTiles(playerRemoved), ["player"])
assert.deepEqual(TileLayout.removeSection(playerRemoved, "system").sections.map((entry) => entry.id), ["weather"])

const resizedCpu = TileLayout.resizeTile(defaults, "cpu", 2, 2)
assert.deepEqual(resizedCpu.tileSizes.cpu, { columns: 2, rows: 2 })
assert.deepEqual(TileLayout.resizeTile(resizedCpu, "cpu", 0, 9).tileSizes.cpu, { columns: 1, rows: 2 })
assert.deepEqual(TileLayout.resizeTile(defaults, "player", 1, 2).tileSizes.player, { columns: 2, rows: 2 })
assert.deepEqual(TileLayout.resizeTile(defaults, "unknown", 1, 1), defaults)
assert.deepEqual(TileLayout.resetTileSize(resizedCpu, "cpu").tileSizes.cpu, defaults.tileSizes.cpu)
const resetSizes = TileLayout.resetSizes(resizedCpu)
assert.deepEqual(resetSizes.tileSizes, defaults.tileSizes)
assert.deepEqual(resetSizes.sections, resizedCpu.sections)

const styled = TileLayout.updateAppearance(defaults, {
  panelOpacity: 0.82,
  tileOpacity: 0.73,
  wallpapers: { light: "light-evening", dark: "dark-forest" },
  wallpaperOpacity: { light: 0.33, dark: 0.58 },
  weatherIconSet: "color"
})
assert.equal(styled.appearance.panelOpacity, 0.82)
assert.equal(styled.appearance.tileOpacity, 0.73)
assert.deepEqual(styled.appearance.wallpapers, { light: "light-evening", dark: "dark-forest" })
assert.deepEqual(styled.appearance.wallpaperOpacity, { light: 0.33, dark: 0.58 })
assert.equal(styled.appearance.weatherIconSet, "color")
const clamped = TileLayout.updateAppearance(styled, {
  panelOpacity: 0.1,
  tileOpacity: 2,
  wallpapers: { light: "missing", dark: "light-evening" },
  wallpaperOpacity: { light: -1, dark: 4 },
  weatherIconSet: "unknown"
})
assert.ok(clamped.appearance.panelOpacity >= 0.65)
assert.equal(clamped.appearance.tileOpacity, 1)
assert.deepEqual(clamped.appearance.wallpapers, styled.appearance.wallpapers)
assert.equal(clamped.appearance.wallpaperOpacity.light, 0)
assert.equal(clamped.appearance.wallpaperOpacity.dark, 1)
assert.equal(clamped.appearance.weatherIconSet, "color")

const reset = TileLayout.resetLayout()
assert.deepEqual(reset, defaults)

console.log("widget layout v2 tests passed")
