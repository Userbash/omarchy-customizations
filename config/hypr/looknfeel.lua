-- Subtle wallpaper blur behind the desktop dashboard's translucent surface.
hl.config({
  decoration = {
    blur = {
      enabled = true,
      size = 10,
      passes = 3,
      vibrancy = 0.18,
      vibrancy_darkness = 0.12,
      noise = 0.012,
    },
  },
})

hl.layer_rule({
  name = "omarchy-widgets-dashboard",
  match = { namespace = "^omarchy-widgets$" },
  blur = true,
  ignore_alpha = 0.10,
})
