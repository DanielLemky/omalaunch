import Quickshell
import QtQuick
import "omalaunch" as Omalaunch

// Interactive development harness. `tests/dev-shell.sh` builds a scratch shell
// root that symlinks Omarchy's real Commons/Ui modules next to this checkout,
// so the launcher can be driven from a source tree without installing it as an
// Omarchy plugin. AGENTS.md rules that out: Omarchy watches its plugin
// directory recursively and reloads the shell for every file changed beneath
// it.
//
// The harness quits as soon as the launcher closes, so Escape always returns
// the keyboard to the desktop. It supplies no AppLibrary, so application rows
// and the Apps menu stay empty; everything else behaves normally.
ShellRoot {
  id: harness

  readonly property string sourceDir: Quickshell.env("OMALAUNCH_DEV_SOURCE")
  readonly property string initialMenu: Quickshell.env("OMALAUNCH_DEV_MENU") || "root"
  readonly property string capability: Quickshell.env("OMALAUNCH_DEV_CAPABILITY")
  property bool started: false

  property var appLibrary: null

  function hide(id) { Qt.quit() }

  Omalaunch.Menu {
    id: menu
    shell: harness
    manifest: ({ id: "quantumfire.omalaunch", __sourceDir: harness.sourceDir })

    onOpenedChanged: if (harness.started && !menu.opened) Qt.quit()
  }

  // Extensions load asynchronously, so entering one has to wait for the
  // catalog rather than run from Component.onCompleted.
  Timer {
    id: enterCapability
    interval: 250
    repeat: true
    running: harness.capability.length > 0
    onTriggered: {
      if (menu.extensions.length === 0) return
      running = false
      var extension = menu.extensionByCapability(harness.capability)
      if (!extension) {
        console.warn("dev-shell: no extension provides capability " + harness.capability)
        return
      }
      console.log("dev-shell: entering " + extension.id + " (" + extension.mode + ")")
      menu.activateExtensionRoot(extension)
    }
  }

  Component.onCompleted: {
    menu.open(JSON.stringify({ initialMenu: harness.initialMenu }))
    harness.started = true
  }
}
