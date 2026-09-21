-- Apple Liquid Glass only for the user's widget surface.
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
  name = "omarchy-custom-widgets-liquid-glass",
  match = { namespace = "^omarchy-custom-widgets$" },
  blur = true,
  ignore_alpha = 0.10,
})
