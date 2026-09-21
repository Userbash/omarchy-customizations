-- User overrides loaded after the Omarchy defaults.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

omarchy_preinstalled_bindings = false

require("default.hypr.omarchy")

hl.env("PATH", table.concat({
  (os.getenv("HOME") or "") .. "/.local/bin",
  (os.getenv("HOME") or "") .. "/.local/share/npm/bin",
  (os.getenv("HOME") or "") .. "/.local/share/fnm/aliases/default/bin",
  os.getenv("PATH") or "/usr/local/bin:/usr/bin:/bin",
}, ":"))

require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

require("default.hypr.toggles")
