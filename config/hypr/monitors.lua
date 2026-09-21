-- Optional monitor override. Set OMARCHY_MONITOR on machines that need it.
local output = os.getenv("OMARCHY_MONITOR")
if output and output ~= "" then
  hl.monitor({
    output = output,
    position = "0x0",
    scale = tonumber(os.getenv("OMARCHY_SCALE") or "1.0"),
    transform = 0,
  })
end

local omarchy_gdk_scale = 2
hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
