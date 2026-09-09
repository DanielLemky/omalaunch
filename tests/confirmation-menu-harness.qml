import Quickshell
import QtQuick
import ".."

ShellRoot {
  FloatingWindow {
    visible: false
    width: 640
    height: 480

    ConfirmationMenu {
      id: menu
      anchors.fill: parent
      opened: true
      actionText: "Run"
      onCanceled: test.cancelCount += 1
      onConfirmed: test.confirmCount += 1
    }
  }

  QtObject {
    id: test
    property int cancelCount: 0
    property int confirmCount: 0
  }

  Timer {
    interval: 10
    running: true
    onTriggered: {
      function key(code) { return { key: code, modifiers: Qt.NoModifier } }
      function reopen(actionFirst, defaultChoice) {
        menu.opened = false
        menu.actionFirst = actionFirst
        menu.defaultChoice = defaultChoice
        menu.resultOnly = false
        menu.opened = true
      }

      if (menu.selectedIndex !== menu.cancelIndex()) throw new Error("Cancel is not the safe default")
      menu.handleKey(key(Qt.Key_Down))
      menu.handleKey(key(Qt.Key_Return))
      if (test.confirmCount !== 1) throw new Error("Cancel-first action activation failed")

      reopen(true, "cancel")
      if (menu.selectedIndex !== 1 || menu.cancelIndex() !== 1) throw new Error("Order changed the cancel default")
      menu.handleKey(key(Qt.Key_Up))
      menu.handleKey(key(Qt.Key_Return))
      if (test.confirmCount !== 2) throw new Error("Action-first mapping failed")

      reopen(false, "action")
      if (menu.selectedIndex !== 1) throw new Error("Action default did not work with cancel-first order")
      menu.handleKey(key(Qt.Key_Escape))
      if (test.cancelCount !== 1 || test.confirmCount !== 2) throw new Error("Escape did not always cancel")

      reopen(true, "action")
      if (menu.selectedIndex !== 0) throw new Error("Action default did not work with action-first order")
      menu.handleKey(key(Qt.Key_Escape))
      if (test.cancelCount !== 2) throw new Error("Escape ran the selected action")

      menu.resultOnly = true
      menu.handleKey(key(Qt.Key_Enter))
      if (test.confirmCount !== 3 || menu.optionCount() !== 1) throw new Error("Result OK row failed")
      console.log("HARNESS_OK confirmation menu order default and escape behavior")
      Qt.quit()
    }
  }
}
