import Quickshell
import Quickshell.Io
import "./widgets" as Widgets

ShellRoot {
  Widgets.Main { id: dashboard }

  IpcHandler {
    target: "widgets.test"

    function state(): string {
      return JSON.stringify({
        layout: dashboard.widgetLayout,
        layoutLoaded: dashboard.layoutLoaded,
        editing: dashboard.editing,
        editorTab: dashboard.editorTab,
        playerTarget: dashboard.playerTarget,
        playerStatus: dashboard.playerStatus,
        playerTitle: dashboard.title,
        playerVolume: dashboard.playerVolume,
        rememberedVolume: dashboard.rememberedPlayerVolume,
        playerMuted: dashboard.playerMuted,
        volumeAvailable: dashboard.playerVolumeAvailable,
        volumeControlEnabled: dashboard.playerVolumeControlEnabled,
        volumeSliderEnabled: dashboard.playerVolumeSliderEnabled,
        muteButtonEnabled: dashboard.playerMuteButtonEnabled,
        volumeWritePending: dashboard.volumeWritePending,
        weatherTemp: dashboard.weatherTemp,
        weatherDesc: dashboard.weatherDesc,
        weatherMeta: dashboard.weatherMeta,
        weatherWind: dashboard.weatherWind,
        positionSeconds: dashboard.positionSeconds,
        durationSeconds: dashboard.durationSeconds
      })
    }

    function available(): string { return JSON.stringify(dashboard.availableTileIds()) }
    function edit(): void { dashboard.editing = true }
    function finish(): void { dashboard.editing = false }
    function tab(value: string): void { dashboard.editorTab = value }
    function theme(value: string): void { dashboard.setTheme(value) }
    function addSection(value: string): void { dashboard.addSection(value) }
    function removeSection(value: string): void { dashboard.removeSection(value) }
    function renameSection(id: string, title: string): void { dashboard.renameSection(id, title) }
    function addTile(tile: string, section: string): void { dashboard.addTile(tile, section) }
    function removeTile(tile: string): void { dashboard.removeTile(tile) }
    function moveTile(tile: string, section: string, target: string, after: bool): void {
      dashboard.moveTile(tile, section, target, after)
    }
    function moveSection(section: string, offset: int): void { dashboard.moveSection(section, offset) }
    function moveSectionTo(section: string, target: string, after: bool): void {
      dashboard.moveSectionTo(section, target, after)
    }
    function setLocked(value: bool): void { dashboard.setLayoutLocked(value) }
    function resizeTile(tile: string, width: int, height: int): void { dashboard.resizeTile(tile, width, height) }
    function resetTileSize(tile: string): void { dashboard.resetTileSize(tile) }
    function resetSizes(): void { dashboard.resetSizes() }
    function resetLayout(): void { dashboard.resetLayout() }
    function wallpaper(theme: string, value: string): void { dashboard.setWallpaper(theme, value) }
    function wallpaperOpacity(theme: string, value: real): void { dashboard.setWallpaperOpacity(theme, value) }
    function appearance(key: string, value: real): void {
      var patch = {}
      patch[key] = value
      dashboard.setAppearance(patch)
    }
    function icons(value: string): void { dashboard.setAppearance({ weatherIconSet: value }) }
    function volume(value: real): void { dashboard.setPlayerVolume(value) }
    function previewVolume(value: real): void {
      dashboard.previewPlayerVolume(value)
      dashboard.endPlayerVolume()
    }
    function volumeUp(): void { dashboard.adjustPlayerVolume(0.05) }
    function volumeDown(): void { dashboard.adjustPlayerVolume(-0.05) }
    function mute(): void { dashboard.toggleMute() }
    function refreshVolume(): void { dashboard.requestPlayerVolume() }
    function togglePlayback(): void { dashboard.togglePlayback() }
    function stopPlayback(): void { dashboard.stopPlayback() }
    function seekBy(value: real): void { dashboard.seekBy(value) }
    function seekTo(value: real): void {
      dashboard.seeking = true
      dashboard.seekTo(value)
    }
    function endSeek(): void { dashboard.endSeek() }
  }
}
