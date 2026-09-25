const fs = require("fs")
const vm = require("vm")
const source = fs.readFileSync(require("path").join(__dirname, "..", "SpectrumParser.js"), "utf8")
const sandbox = {}
vm.createContext(sandbox)
vm.runInContext(source, sandbox)
const Parser = sandbox.SpectrumParser

function check(condition, label) {
  if (!condition) throw new Error(label)
  console.log("ok - " + label)
}

const parsed = Parser.parse("0 50 100", 5)
check(parsed.bands.length === 5, "parser always returns requested band count")
check(parsed.bands[0] === 0 && parsed.bands[1] === 0.5 && parsed.bands[2] === 1, "parser normalizes valid values")
check(parsed.bands[3] === 0 && parsed.bands[4] === 0, "parser pads short lines")
check(parsed.peak === 1 && parsed.energy === 0.3, "parser calculates energy and peak")

const malformed = Parser.parse("-10 NaN Infinity 240", 4)
check(malformed.bands[0] === 0 && malformed.bands[1] === 0 && malformed.bands[2] === 0, "parser rejects malformed values")
check(malformed.bands[3] === 1, "parser clamps oversized values")
check(Parser.parse("1;2;3", 3).bands[2] === 0.03, "parser accepts semicolon protocol")
check(Parser.parse("", 0).energy === 0, "parser handles zero band count")
