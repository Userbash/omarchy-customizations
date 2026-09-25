// Pure parser for Cava's ASCII spectrum stream.
// It intentionally has no Qt, filesystem, process, or network dependencies.
var SpectrumParser = {
  clamp: function(value) {
    var number = Number(value)
    if (!isFinite(number)) return 0
    return Math.max(0, Math.min(1, number))
  },

  parse: function(line, count) {
    var bandCount = Math.max(0, Math.floor(Number(count) || 0))
    var fields = String(line || "").trim().split(/[;\s]+/)
    var bands = []
    var total = 0
    var peak = 0
    for (var i = 0; i < bandCount; i++) {
      var raw = i < fields.length ? parseFloat(fields[i]) : 0
      var value = isFinite(raw) ? this.clamp(raw / 100) : 0
      bands.push(value)
      total += value
      peak = Math.max(peak, value)
    }
    return {
      bands: bands,
      energy: bandCount > 0 ? total / bandCount : 0,
      peak: peak
    }
  }
}
