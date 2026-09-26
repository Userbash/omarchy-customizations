const assert = require("node:assert/strict")
const model = require("../config/omarchy/plugins/weather/Model.js")

assert.deepEqual(model.parseLocationFile('{"name":" Berlin ","latitude":"52.52","longitude":13.405}'), {
  name: "Berlin", latitude: 52.52, longitude: 13.405
})
assert.deepEqual(model.parseLocationFile('{"name":"Test","latitude":"91","longitude":181}'), {
  name: "Test", latitude: null, longitude: null
})
assert.equal(model.parseCoordinate("12.5junk", -90, 90), null)
assert.equal(model.parseCoordinate("1e3", -90, 90), null)
assert.equal(model.wttrLocationQuery("A & B", null, null), "A%20%26%20B")
assert.equal(model.wttrLocationQuery("Fallback", "91", "0"), "Fallback")
assert.equal(model.locationCommit("x".repeat(200), [], 0).name.length, 128)
assert.equal(model.parseGeocodingResults(JSON.stringify({ results: [
  { name: "Good", latitude: 51.5, longitude: -0.12 },
  { name: "Bad", latitude: 91, longitude: 0 }
] })).length, 1)
process.stdout.write("weather model validation tests: ok\n")
