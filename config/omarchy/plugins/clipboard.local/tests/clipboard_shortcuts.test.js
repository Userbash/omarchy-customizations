const assert = require('node:assert/strict')
const shortcuts = require('../KeyboardActions.js')

const action = (key, modifiers = {}) => shortcuts.actionFor(key, modifiers)

assert.equal(action('S', { ctrl: true }), '')
assert.equal(action('P', { ctrl: true }), '')
assert.equal(action('Delete', { ctrl: true }), 'clearAll')
assert.equal(action('Return'), 'paste')
assert.equal(action('Return', { shift: true }), 'copy')
assert.equal(action('Return', { alt: true }), 'open')
assert.equal(action('Escape'), 'close')

for (const input of [
  ['S', {}], ['P', {}], ['Delete', {}], ['S', { alt: true }],
  ['S', { ctrl: true }], ['P', { ctrl: true }],
  ['Return', { ctrl: true }], ['Escape', { shift: true }], ['Unknown', { ctrl: true }]
]) assert.equal(action(input[0], input[1]), '', `${input[0]} must not trigger an action`)

const labels = shortcuts.labels()
assert.match(labels.clearAll, /Ctrl\+Del/)
assert.ok(labels.clearAll.length < 30, 'clear-all label must fit the footer')
console.log('clipboard shortcut tests: ok')
