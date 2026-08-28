import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy"
  readonly property string statePath: stateDir + "/starred-launcher-items.json"
  property var starredIds: ({})
  property bool directoryReady: false
  property bool loaded: false

  signal changed()

  function load(rawText) {
    var next = ({})
    try {
      var parsed = JSON.parse(String(rawText || "{}"))
      var ids = parsed && parsed.version === 1 && Array.isArray(parsed.ids) ? parsed.ids : []
      for (var i = 0; i < ids.length; i++) {
        var id = String(ids[i] || "")
        if (id) next[id] = true
      }
    } catch (e) {
      next = ({})
    }
    root.starredIds = next
    root.loaded = true
    root.changed()
  }

  function isStarred(itemId) {
    return root.starredIds[String(itemId || "")] === true
  }

  function save(next) {
    var ids = Object.keys(next).filter(function(id) { return next[id] === true }).sort()
    stateFile.setText(JSON.stringify({ version: 1, ids: ids }, null, 2) + "\n")
  }

  function toggle(itemId) {
    var id = String(itemId || "")
    if (!root.loaded || !id) return
    var next = Object.assign({}, root.starredIds)
    if (next[id] === true) delete next[id]
    else next[id] = true
    root.starredIds = next
    root.save(next)
    root.changed()
  }

  Process {
    id: initDir
    command: ["mkdir", "-p", root.stateDir]
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
