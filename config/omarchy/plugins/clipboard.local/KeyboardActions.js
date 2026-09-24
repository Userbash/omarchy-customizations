// Keyboard shortcuts are intentionally scoped to the clipboard overlay: the
// QML key catcher calls this map only while the overlay owns keyboard focus.
function actionFor(key, modifiers) {
  var mods = modifiers || {}
  var normalized = String(key || "")
  if (normalized === "Escape" && !mods.ctrl && !mods.alt && !mods.shift) return "close"
  if (normalized === "Return") {
    if (mods.ctrl) return ""
    if (mods.alt && !mods.ctrl) return "open"
    if (mods.shift && !mods.ctrl && !mods.alt) return "copy"
    if (!mods.shift && !mods.alt) return "paste"
  }
  if (normalized === "S" && mods.ctrl && !mods.alt && !mods.shift) return "saveAs"
  if (normalized === "P" && mods.ctrl && !mods.alt && !mods.shift) return "pin"
  if (normalized === "Delete" && mods.ctrl && !mods.alt && !mods.shift) return "clearAll"
  return ""
}

function labels() {
  return {
    saveAs: "Save (Ctrl+S)",
    pin: "Pin (Ctrl+P)",
    clearAll: "Очистить (Ctrl+Del)"
  }
}

if (typeof module !== "undefined") {
  module.exports = { actionFor: actionFor, labels: labels }
}
