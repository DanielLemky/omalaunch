import QtQuick
import Quickshell

// Permanent regression coverage for Menu.qml, independent of any fallback.
ShellRoot {
  id: root
  property var fixture: null
  property int merges: 0
  property bool lastLibraryWasNull: false
  property int stage: 0
  property double stageStarted: Date.now()
  property bool failed: false

  function check(value, message) {
    if (value) return
    root.failed = true
    console.error("HARNESS_FAIL", message)
    Qt.quit()
  }
  function next() {
    root.stage++
    root.stageStarted = Date.now()
  }

  Item { id: fixtureParent }
  Component {
    id: fixtureComponent
    AppLibraryReconciliationFixture {
      onMerged: function(emptyLibrary) {
        root.merges++
        root.lastLibraryWasNull = emptyLibrary
      }
    }
  }

  Component.onCompleted: {
    root.fixture = fixtureComponent.createObject(fixtureParent)
    root.fixture.appLibrary = ({ first: true })
    root.fixture.appLibrary = ({ second: true })
  }

  Timer {
    interval: 10
    repeat: true
    running: true
    onTriggered: {
      if (root.failed) return
      var elapsed = Date.now() - root.stageStarted
      root.check(elapsed < 3000, "timeout at stage " + root.stage)
      if (root.failed || elapsed < 200) return
      switch (root.stage) {
        case 0:
          root.check(root.merges === 1, "library handoff must coalesce reconciliation")
          root.fixture.appLibrary = null
          root.next()
          break
        case 1:
          root.check(root.merges === 2 && root.lastLibraryWasNull, "live detachment must reconcile an empty library")
          root.fixture.appLibrary = ({ pending: true })
          root.fixture.providersLoaded = ({})
          root.next()
          break
        case 2:
          root.check(root.merges === 2, "queued reconciliation must check the current provider state")
          root.fixture.providersLoaded = ({apps: true})
          root.fixture.appLibrary = null
          root.fixture.destroy()
          root.next()
          break
        case 3:
          root.check(root.merges === 2, "queued reconciliation must not outlive the menu")
          if (!root.failed) console.log("HARNESS_OK app library reconciliation lifecycle")
          Qt.quit()
          break
      }
    }
  }
}
