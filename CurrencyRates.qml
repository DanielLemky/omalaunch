import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy"
  readonly property string statePath: stateDir + "/launcher-currency-rates.json"
  readonly property int cooldownMs: 15 * 60 * 1000
  property double lastSuccessfulRefreshAt: 0
  property bool directoryReady: false
  property bool loaded: false

  signal refreshed()
  signal refreshFailed()

  function load(rawText) {
    try {
      var parsed = JSON.parse(String(rawText || "{}"))
      root.lastSuccessfulRefreshAt = parsed && parsed.version === 1
        ? Math.max(0, Number(parsed.lastSuccessfulRefreshAt) || 0)
        : 0
    } catch (e) {
      root.lastSuccessfulRefreshAt = 0
    }
    root.loaded = true
  }

  function refreshIfStale() {
    if (!root.loaded || refreshProc.running) return
    if (Date.now() - root.lastSuccessfulRefreshAt < root.cooldownMs) return
    refreshProc.running = true
  }

  Process {
    id: initDir
    command: ["mkdir", "-p", root.stateDir]
    onExited: root.directoryReady = true
  }

  Process {
    id: refreshProc
    command: ["qalc", "-e", "-t", "-m", "10000", "1"]
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.refreshFailed()
        return
      }
      root.lastSuccessfulRefreshAt = Date.now()
      stateFile.setText(JSON.stringify({
        version: 1,
        lastSuccessfulRefreshAt: root.lastSuccessfulRefreshAt
      }, null, 2) + "\n")
      root.refreshed()
    }
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
