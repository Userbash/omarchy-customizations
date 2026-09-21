.pragma library

// User-owned adapter boundary. The current shell backend remains compatible
// with JSON history; SQLite migration is staged and will be wired here only
// after the QML/runtime gate passes.
function getItems(filter, query) { return [] }
function getItem(id) { return id }
function searchItems(query) { return getItems("all", query) }
function copyItem(id) { return id }
function deleteItem(id) { return id }
function pinItem(id, pinned) { return { id: id, pinned: !!pinned } }
function clearHistory(options) { return options || {} }
function clearSystemClipboard() { return true }
function getStats() { return { total: 0, bytes: 0, freeBytes: 250 * 1024 * 1024 } }
function requestPreview(id) { return id }
function saveAs(id, path) { return { id: id, path: path } }
