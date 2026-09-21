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

check(CatMotion.frameCount === 144, "motion cycle is sampled for a 144 Hz display")
check(CatMotion.clamp(-2, 0, 1) === 0 && CatMotion.clamp(2, 0, 1) === 1, "motion clamps untrusted inputs")
const eased = CatMotion.smooth(0, 1, 1 / 144, 2.4)
check(eased > 0 && eased < 0.03, "tempo easing advances in small continuous steps")
const left = CatMotion.nextPosition({ x: 1, y: 20, vx: -40, vy: 0 }, 700, 180, 0.15)
check(left.x >= 0 && left.vx === 0, "cat settles safely at the left edge")
const right = CatMotion.nextPosition({ x: 587, y: 20, vx: 40, vy: 0 }, 700, 180, 0.15)
check(right.x <= 588 && right.vx === 0, "cat settles safely at the right edge")
const pose = CatMotion.pose(24, 0.7, true)
check(Number.isFinite(pose.bob) && Number.isFinite(pose.tail) && pose.scaleX > 1, "frame pose is finite and reacts to music")
const landed = CatMotion.nextPosition({ x: 500, y: 500, vx: 1, vy: 200 }, 1000, 360, 0.04)
check(landed.y === 214 && landed.vy === 0, "fall settles on the lower-stage floor")
const capped = CatMotion.nextPosition({ x: 200, y: 20, vx: 900, vy: -900 }, 1000, 360, 0.04)
check(capped.vx === 380 && capped.vy > -420, "movement speed remains bounded during a jump")
