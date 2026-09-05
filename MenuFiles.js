function actionDefinitions(type, starred, agentToolsAvailable) {
  var actions = type === "directory"
    ? [
        { id: "open-files", icon: "󰉋", label: "Open in Files" },
        { id: "open-terminal", icon: "", label: "Open in terminal" }
      ]
    : [
        { id: "open", icon: "󰈔", label: "Open" },
        { id: "show-files", icon: "󰉋", label: "Show in Files" }
      ]

  if (agentToolsAvailable)
    actions.push({ id: "start-agent", icon: "󰚩", label: "Start Agent Here" })

  actions.push({ id: "toggle-star", icon: "★", label: starred ? "Unstar" : "Star" })
  actions.push({ id: "copy-path", icon: "󰆏", label: "Copy path" })
  if (type === "file")
    actions.push({ id: "copy-file", icon: "󰆏", label: "Copy file to clipboard" })
  return actions
}

function restoredBrowserState(panelFile) {
  return {
    filter: panelFile ? String(panelFile.filter || "") : "",
    index: panelFile ? Number(panelFile.index || 0) : 0,
    itemId: panelFile ? String(panelFile.itemId || "") : "",
    path: panelFile ? String(panelFile.path || "") : "",
    type: panelFile ? String(panelFile.type || "") : ""
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    actionDefinitions: actionDefinitions,
    restoredBrowserState: restoredBrowserState
  }
}
