// Deterministic motion backend for the desktop cat.  It has no filesystem,
// process, or network access; all input is numeric and bounded before use.
var CatMotion = {
  // The pose cycle is sampled at the display's 144 Hz refresh rate. Fractional
  // frames are also supported, so rendering stays smooth between samples.
  frameCount: 144,

  clamp: function(value, low, high) {
    var number = Number(value)
    if (!isFinite(number)) return low
    return Math.max(low, Math.min(high, number))
  },

  smooth: function(value, target, seconds, response) {
    var current = Number(value) || 0
    var desired = Number(target) || 0
    var dt = this.clamp(seconds, 0, 0.2)
    var rate = this.clamp(response, 0, 30)
    return current + (desired - current) * (1 - Math.exp(-rate * dt))
  },

  pose: function(frame, energy, facingRight) {
    var phase = (this.clamp(frame, 0, this.frameCount - 1) / this.frameCount) * Math.PI * 2
    var music = this.clamp(energy, 0, 1)
    return {
      // Gentle, continuous poses: no hard frame changes or sudden squash.
      bob: Math.sin(phase * 2) * (1.5 + music * 4),
      tail: Math.sin(phase * 1.5 + 0.5) * (6 + music * 11),
      lean: Math.sin(phase) * (1 + music * 2.5),
      scaleX: (facingRight ? 1 : -1) * (1 + music * 0.05),
      scaleY: 1 - music * 0.04 - Math.max(0, Math.sin(phase * 2)) * 0.018
    }
  },

  nextPosition: function(state, stageWidth, stageHeight, seconds) {
    var maxX = Math.max(0, Number(stageWidth) - 112)
    var floorY = Math.max(0, Number(stageHeight) - 146)
    var dt = this.clamp(seconds, 0, 0.2)
    var x = this.clamp(state.x, 0, maxX) + this.clamp(state.vx, -380, 380) * dt
    var y = this.clamp(state.y, 0, floorY) + this.clamp(state.vy, -420, 420) * dt
    var vx = this.clamp(state.vx, -380, 380)
    var vy = this.clamp(state.vy, -420, 420) + 850 * dt
    // Stop softly at edges and the floor rather than bouncing back.
    if (x <= 0) { x = 0; if (vx < 0) vx = 0 }
    if (x >= maxX) { x = maxX; if (vx > 0) vx = 0 }
    if (y >= floorY) { y = floorY; if (vy > 0) vy = 0 }
    if (y <= 0) { y = 0; if (vy < 0) vy = 0 }
    return { x: x, y: y, vx: vx, vy: vy }
  }
}
