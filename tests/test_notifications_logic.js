const assert = require("node:assert/strict")
const logic = require("../config/omarchy/plugins/notifications.local/NotificationLogic.js")

function test(name, fn) {
  fn()
  process.stdout.write(`PASS — ${name}\n`)
}

test("image tags are removed before StyledText rendering", () => {
  const body = "hello <img src='https://example.invalid/x.png'> world"
  assert.equal(logic.styledBody(body, "app", ""), "hello  world")
})

test("non-image markup is retained for the documented body capability", () => {
  assert.equal(logic.styledBody("<b>hello</b>", "app", ""), "<b>hello</b>")
})

test("malformed executable hints fail closed", () => {
  assert.equal(logic.parseExecArgv("not-json"), null)
  assert.equal(logic.parseExecArgv(JSON.stringify(["-c", "echo unsafe"])), null)
  assert.deepEqual(Array.from(logic.parseExecArgv(JSON.stringify(["bash", "-c", "echo ok"]))), ["bash", "-c", "echo ok"])
})

test("DND bypass is restricted to trusted action sources", () => {
  assert.equal(logic.shouldBypassDnd({ appName: "omarchy-action", urgency: 0 }, 2), true)
  assert.equal(logic.shouldBypassDnd({ appName: "notify-send", urgency: 2 }, 2), true)
  assert.equal(logic.shouldBypassDnd({ appName: "Discord", urgency: 2 }, 2), false)
})

test("history replay deduplicates by persisted file identity", () => {
  const row = { originalId: 1, timestamp: 1000, summary: "one" }
  const rows = logic.historyRows(JSON.stringify(row), [row], 1, 10)
  assert.equal(rows.length, 1)
  assert.equal(rows[0].summary, "one")
})
