import QtQuick
import Quickshell
import "app-library-fallback-state.js" as State

ShellRoot {
  id: root
  property var access: null
  property var reconciliationFixture: null
  property var lastRows: []
  property int stage: 0
  property double stageStarted: Date.now()
  property bool failed: false

  function check(value, message) {
    if (value) return
    root.failed = true
    console.error("HARNESS_FAIL", message)
    Qt.quit()
  }
  function reconcile() {
    root.lastRows = root.access && root.access.library
      ? root.access.library.sortedEntries("") : []
  }
  function next() {
    root.stage++
    root.stageStarted = Date.now()
  }
  function ready() { return root.access && root.access.fallbackStatus === Loader.Ready }

  QtObject {
    id: shared
    signal appsChanged()
    function sortedEntries(query) { return [{ entry: { id: "shared" } }] }
  }

  Component {
    id: accessComponent
    LauncherAppLibrary {
      omarchyPath: "/fixture/omarchy"
      fallbackSource: Qt.resolvedUrl("app-library-fallback-fixture.qml")
      onLibraryChanged: root.reconcile()
    }
  }
  Component {
    id: reconciliationComponent
    AppLibraryReconciliationFixture { }
  }
  Connections {
    target: root.access ? root.access.library : null
    function onAppsChanged() { root.reconcile() }
  }

  Component.onCompleted: {
    root.access = accessComponent.createObject(root)
    root.check(root.access.library === null, "detached library must be null")
    root.check(root.access.fallbackStatus === Loader.Null, "detached fallback must be inactive")
    root.access.sharedLibrary = shared
    root.access.fallbackEnabled = true
  }

  Timer {
    interval: 10
    repeat: true
    running: true
    onTriggered: {
      if (root.failed) return
      var elapsed = Date.now() - root.stageStarted
      root.check(elapsed < 3000, "timeout at stage " + root.stage)
      if (root.failed) return
      switch (root.stage) {
        case 0:
          if (elapsed < 50) return
          root.check(State.created === 0, "shared host must never instantiate fallback")
          root.check(root.access.library === shared, "shared identity must be retained")
          root.access.fallbackSource = Qt.resolvedUrl("missing-while-shared.qml")
          root.check(root.access.fallbackStatus === Loader.Null, "a shared host must not attempt fallback sources")
          root.access.fallbackSource = Qt.resolvedUrl("app-library-fallback-fixture.qml")
          root.access.sharedLibrary = null
          root.next()
          break
        case 1:
          if (!root.ready()) return
          root.check(State.created === 1, "missing shared capability must create one fallback")
          root.check(State.initializedPath === "/fixture/omarchy", "path must be set before service startup")
          root.check(root.lastRows.length === 1 && root.lastRows[0].entry.id === "fallback", "late library arrival must reconcile rows")
          root.check(root.access.library.iconSource("app") === "fixture:app", "icon method must come from selected library")
          root.access.library.changeRows()
          root.check(root.lastRows[0].entry.id === "changed", "active app changes must reconcile rows")
          root.access.library.launch("app", "App")
          root.access.sharedLibrary = shared
          root.check(root.access.library === shared, "shared library must take priority on handoff")
          root.next()
          break
        case 2:
          if (elapsed < 100) return
          root.check(State.destroyed === 1 && State.cleanups === 1, "handoff must clean up before destruction")
          root.check(State.osdShows === 0, "teardown before launch delay must cancel feedback")
          root.check(root.lastRows.length === 1 && root.lastRows[0].entry.id === "shared", "no fallback rows may survive handoff")
          root.access.sharedLibrary = null
          root.next()
          break
        case 3:
          if (!root.ready()) return
          root.check(State.created === 2, "lost shared capability must recreate fallback")
          root.access.library.launch("app", "App")
          root.next()
          break
        case 4:
          if (elapsed < 100) return
          root.check(State.osdShows === 1, "launch fixture must show feedback")
          root.access.fallbackEnabled = false
          root.check(root.access.library === null, "detachment must clear the effective library")
          root.check(root.lastRows.length === 0, "detachment must clear stale rows")
          root.next()
          break
        case 5:
          if (elapsed < 30) return
          root.check(State.destroyed === 2 && State.osdCloses === 1, "detachment must close an open OSD")
          root.access.fallbackEnabled = true
          root.next()
          break
        case 6:
          if (!root.ready()) return
          root.check(State.created === 3, "reattachment must load fallback")
          root.access.fallbackSource = Qt.resolvedUrl("missing-app-library.qml")
          root.next()
          break
        case 7:
          if (root.access.fallbackStatus !== Loader.Error || elapsed < 100) return
          root.check(State.destroyed === 3, "source replacement must clean up the old service")
          root.check(root.access.library === null && root.lastRows.length === 0, "load errors must not retain stale rows")
          root.access.syncFallback()
          root.access.syncFallback()
          root.access.sharedLibrary = shared
          root.check(root.access.library === shared, "shared capability must recover from fallback error")
          root.access.fallbackEnabled = false
          root.access.sharedLibrary = null
          root.access.fallbackSource = Qt.resolvedUrl("app-library-fallback-fixture.qml")
          root.access.fallbackEnabled = true
          root.next()
          break
        case 8:
          if (!root.ready()) return
          root.check(State.created === 4, "valid source must recover after error")
          root.access.library.launch("app", "App")
          root.next()
          break
        case 9:
          if (elapsed < 100) return
          root.check(State.osdShows === 2, "second launch must show feedback")
          root.access.destroy()
          root.next()
          break
        case 10:
          if (elapsed < 50) return
          root.check(State.destroyed === 4 && State.osdCloses === 2, "wrapper destruction must close owned feedback")
          root.check(State.unsafeDestructions === 0, "all owned launch state must be stopped before destruction")
          root.check(State.cleanups === 4, "each owned instance must be cleaned up exactly once")
          root.reconciliationFixture = reconciliationComponent.createObject(root)
          root.reconciliationFixture.appLibrary = ({ first: true })
          root.reconciliationFixture.appLibrary = ({ second: true })
          root.next()
          break
        case 11:
          if (elapsed < 200) return
          root.check(State.reconciliations === 1, "library handoff must coalesce reconciliation")
          root.reconciliationFixture.appLibrary = null
          root.next()
          break
        case 12:
          if (elapsed < 200) return
          root.check(State.reconciliations === 2 && State.lastLibraryWasNull, "live detachment must reconcile an empty library")
          root.reconciliationFixture.appLibrary = ({ pending: true })
          root.reconciliationFixture.destroy()
          root.next()
          break
        case 13:
          if (elapsed < 200) return
          root.check(State.reconciliations === 2, "queued reconciliation must not outlive the menu")
          if (!root.failed) console.log("HARNESS_OK app library fallback lifecycle")
          Qt.quit()
          break
      }
    }
  }
}
