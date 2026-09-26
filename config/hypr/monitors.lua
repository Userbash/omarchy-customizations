-- Optional monitor override. Set OMARCHY_MONITOR on machines that need it.
local output = os.getenv("OMARCHY_MONITOR")
local scale = tonumber(os.getenv("OMARCHY_SCALE") or "1.0")
if not scale or scale ~= scale or scale <= 0 or scale > 10 then
  scale = 1.0
end

if output and (#output > 128 or output:find("[%c]") or output:match("^%s*$")) then
  output = nil
end

if output and output ~= "" then
  hl.monitor({
    output = output,
    position = "0x0",
    scale = scale,
    transform = 0,
  })
end

local omarchy_gdk_scale = 2
hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
