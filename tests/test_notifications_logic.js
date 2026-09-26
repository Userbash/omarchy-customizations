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

test("notification image sources cannot trigger remote fetches", () => {
  assert.equal(logic.safeImageSource("https://example.invalid/pixel.png", false), "")
  assert.equal(logic.safeImageSource("http://127.0.0.1:8080/", false), "")
  assert.equal(logic.safeImageSource("data:image/png;base64,AAAA", false), "")
  assert.equal(logic.safeImageSource("file://evil.invalid/share/image.png", false), "")
  assert.equal(logic.safeImageSource("file:///tmp/image.png", false), "file:///tmp/image.png")
  assert.equal(logic.safeImageSource("file://localhost/tmp/image.png", false), "file://localhost/tmp/image.png")
  assert.equal(logic.safeImageSource("image://notifications/preview", false), "image://notifications/preview")
  assert.equal(logic.safeImageSource("qrc:/icons/app.svg", false), "qrc:/icons/app.svg")
  assert.equal(logic.safeImageSource("org.example.Player", true), "org.example.Player")
  assert.equal(logic.safeImageSource("https://example.invalid/icon.png", true), "")
  assert.equal(logic.safeImageSource("/tmp/a b.png", false), "file:///tmp/a%20b.png")
  assert.equal(logic.safeImageSource("/tmp/a%20b.png", true), "file:///tmp/a%2520b.png")
  assert.equal(logic.localImageFile("file:///tmp/a%20b.png"), "/tmp/a b.png")
  assert.equal(logic.localImageFile("/tmp/a%20b.png"), "/tmp/a%20b.png")
})

test("persisted notifications discard remote image values", () => {
  const persisted = logic.persistablePopup({
    timestamp: 10,
    originalId: 2,
    appIcon: "https://example.invalid/icon.png",
    image: "https://example.invalid/pixel.png"
  }, "/tmp/notifications/images/")
  assert.equal(persisted.entry.appIcon, "")
  assert.equal(persisted.entry.image, "")
  assert.equal(persisted.copies.length, 0)
})

test("persisted local images use escaped file URLs and preserve literal percent signs", () => {
  const persisted = logic.persistablePopup({
    timestamp: 10,
    originalId: 2,
    appIcon: "/tmp/a%20b.png"
  }, "/tmp/notifications images/")
  assert.equal(persisted.entry.appIcon, "file:///tmp/notifications%20images/10-2-appIcon")
  assert.deepEqual(persisted.copies, [{
    from: "/tmp/a%20b.png",
    to: "/tmp/notifications images/10-2-appIcon"
  }])
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
