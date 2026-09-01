import Quickshell
import QtQuick
import "MenuModel.js" as MenuModel

// Run dynamic-menu normalization in the same QML JavaScript engine as Omalaunch.
ShellRoot {
  Timer {
    interval: 10
    running: true
    onTriggered: {
      var workflow = MenuModel.normalizeDynamicMenuOutput({ items: [
        {
          id: "google",
          label: "Google",
          globalSearch: true,
          trailingIcon: "globe",
          starred: true,
          starAction: "star",
          input: { prompt: "Search Google", command: ["search", "{input}"], closeOnSuccess: true },
          actions: [{ id: "star", label: "Unstar", command: ["state", "star"] }]
        },
        {
          id: "bing",
          label: "Bing",
          globalSearch: false,
          input: { prompt: "Search Bing", command: ["search", "{input}"], closeOnSuccess: true }
        }
      ] })
      var extension = { id: "omalaunch.web-search", capability: "web-search", mode: "menu", icon: "", iconFont: "" }
      var searched = MenuModel.dynamicMenuSearchItems(extension, workflow)
      if (!workflow || workflow.items.length !== 2 || searched.length !== 1
          || searched[0].trailingIcon !== "globe" || workflow.items[0].starAction !== "star") {
        console.error("HARNESS_FAIL dynamic menu normalization")
        Qt.exit(1)
        return
      }
      console.log("HARNESS_OK dynamic menu normalized in QML")
      Qt.quit()
    }
  }
}
