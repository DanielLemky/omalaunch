import Quickshell
import Quickshell.Io
import QtQuick

// Quickshell integration harness for the reusable live-query Process contract.
// The first direct child ignores SIGTERM and emits stale output. The harness
// coalesces two replacements, escalates the old generation to SIGKILL, and
// proves only the latest replacement can publish.
ShellRoot {
  id: root

  property string pending: ""
  property int generation: 0
  property bool stopping: false
  property int stopGeneration: 0
  property string accepted: ""
  property string collected: ""

  function launch(value) {
    if (proc.running || root.stopping) {
      root.pending = value
      return
    }
    root.generation += 1
    proc.generation = root.generation
    proc.value = value
    root.collected = ""
    proc.command = value === "old"
      ? ["python", "-c", "import signal,sys,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); sys.stdout.write('old-stale'); sys.stdout.flush(); time.sleep(3)"]
      : ["python", "-c", "print('" + value + "', end='')"]
    proc.running = true
  }

  function replace(value) {
    root.pending = value
    if (proc.running && !root.stopping) {
      root.stopping = true
      root.stopGeneration = proc.generation
      proc.running = false
      killer.generation = root.stopGeneration
      killer.restart()
    }
  }

  Process {
    id: proc
    property int generation: 0
    property string value: ""
    stdout: StdioCollector { onStreamFinished: root.collected = this.text }
    onExited: function(exitCode) {
      var publish = !root.stopping && proc.value === "latest" && exitCode === 0
      if (publish) root.accepted = root.collected
      root.stopping = false
      root.stopGeneration = 0
      if (root.pending) {
        var value = root.pending
        root.pending = ""
        root.launch(value)
      } else if (root.accepted === "latest") {
        console.log("HARNESS_OK latest accepted; stale output rejected")
        Qt.quit()
      } else {
        console.error("HARNESS_FAIL accepted=" + root.accepted + " collected=" + root.collected)
        Qt.exit(1)
      }
    }
  }

  Timer {
    id: killer
    interval: 100
    property int generation: 0
    onTriggered: {
      if (root.stopping && generation === root.stopGeneration && generation === proc.generation)
        proc.signal(9)
    }
  }
  Timer { interval: 50; running: true; onTriggered: root.replace("superseded") }
  Timer { interval: 75; running: true; onTriggered: root.replace("latest") }
  Timer {
    interval: 5000
    running: true
    onTriggered: {
      console.error("HARNESS_TIMEOUT")
      Qt.exit(2)
    }
  }

  Component.onCompleted: root.launch("old")
}
