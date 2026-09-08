import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy"
  readonly property string statePath: stateDir + "/launcher-usage.json"
  property var records: ({})
  property bool directoryReady: false
  property bool loaded: false

  signal changed()

  function keyIn(map, id) {
    return Object.prototype.hasOwnProperty.call(map, String(id))
  }
  function storeId(map, id, value) {
    Object.defineProperty(map, String(id), { value: value, writable: true, enumerable: true, configurable: true })
    return map
  }

  function load(rawText) {
    var next = ({})
    try {
      var parsed = JSON.parse(String(rawText || "{}"))
      var source = parsed && parsed.version === 1 && parsed.records && typeof parsed.records === "object" ? parsed.records : ({})
      for (var id in source) {
        var record = source[id]
        var count = Math.max(0, Number(record && record.count) || 0)
        var lastUsedAt = Math.max(0, Number(record && record.lastUsedAt) || 0)
        if (id && count > 0 && keyIn(source, id)) storeId(next, id, { count: count, lastUsedAt: lastUsedAt })
      }
    } catch (e) {
      next = ({})
    }
    root.records = next
    root.loaded = true
    root.changed()
  }

  function count(itemId) {
    var record = root.records[String(itemId || "")]
    return record ? Math.max(0, Number(record.count) || 0) : 0
  }

  function lastUsedAt(itemId) {
    var record = root.records[String(itemId || "")]
    return record ? Math.max(0, Number(record.lastUsedAt) || 0) : 0
  }

  function save(next) {
    stateFile.setText(JSON.stringify({ version: 1, records: next }, null, 2) + "\n")
  }

  function record(itemId) {
    var id = String(itemId || "")
    if (!root.loaded || !id) return
    var next = Object.assign({}, root.records)
    var previous = keyIn(next, id) ? next[id] : ({})
    storeId(next, id, {
      count: Math.max(0, Number(previous.count) || 0) + 1,
      lastUsedAt: Date.now()
    })
    root.records = next
    root.save(next)
    root.changed()
  }

  function forget(itemId) {
    var id = String(itemId || "")
    if (!root.loaded || !id || !root.records[id]) return
    var next = Object.assign({}, root.records)
    delete next[id]
    root.records = next
    root.save(next)
    root.changed()
  }

  function reset() {
    if (!root.loaded) return
    root.records = ({})
    root.save(root.records)
    root.changed()
  }

  Process {
    id: initDir
    command: ["install", "-d", "-m", "0700", root.stateDir]
    onExited: root.directoryReady = true
  }

  FileView {
    id: stateFile
    path: root.directoryReady ? root.statePath : ""
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onLoadFailed: if (root.directoryReady) root.load("{}")
  }

  Component.onCompleted: initDir.running = true
}
