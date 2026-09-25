const fs = require("fs")
const vm = require("vm")
const source = fs.readFileSync(require("path").join(__dirname, "..", "CatMotion.js"), "utf8")
const sandbox = {}
vm.createContext(sandbox)
vm.runInContext(source, sandbox)
const CatMotion = sandbox.CatMotion
function check(condition, label) {
  if (!condition) throw new Error(label)
  console.log("ok - " + label)
}
check(CatMotion.clamp(NaN, 0, 1) === 0, "NaN clamp is finite")
check(CatMotion.clamp(Infinity, 0, 1) === 0, "infinite clamp is rejected")
check(CatMotion.smooth(NaN, 1, 0.1, 2) === 1 - Math.exp(-0.2), "smooth handles invalid current value")
const invalidStage = CatMotion.nextPosition({x: 10, y: 10, vx: 1, vy: 1}, NaN, NaN, 1)
check(Number.isFinite(invalidStage.x) && Number.isFinite(invalidStage.y), "invalid stage sizes cannot create NaN position")
const tinyStage = CatMotion.nextPosition({x: 20, y: 20, vx: 100, vy: 100}, 50, 50, 0.1)
check(tinyStage.x === 0 && tinyStage.y === 0, "tiny stage clamps to safe origin")
