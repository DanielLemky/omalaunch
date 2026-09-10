import QtQuick
import "app-library-fallback-state.js" as State

Item {
  id: root
  property string omarchyPath: "unset"
  property var rows: [{ entry: { id: "fallback", name: "Fallback app" } }]
  property int launchSerial: 0
  property bool launchPending: false
  property bool launchOsdOpen: false
  signal appsChanged()

  function sortedEntries(query) { return root.rows }
  function iconSource(icon) { return "fixture:" + icon }
  function changeRows() {
    root.rows = [{ entry: { id: "changed", name: "Changed app" } }]
    root.appsChanged()
  }
  function launch(id, name) {
    root.launchSerial++
    root.launchPending = true
    delay.restart()
  }
  function closeLaunchFeedback(serial) {
    if (serial !== root.launchSerial) return
    State.cleanups++
    delay.stop()
    root.launchPending = false
    if (root.launchOsdOpen) State.osdCloses++
    root.launchOsdOpen = false
  }

  Timer {
    id: delay
    interval: 40
    onTriggered: {
      root.launchOsdOpen = true
      State.osdShows++
    }
  }
  Component.onCompleted: {
    State.created++
    State.initializedPath = root.omarchyPath
  }
  Component.onDestruction: {
    State.destroyed++
    if (root.launchPending || root.launchOsdOpen) State.unsafeDestructions++
  }
}
