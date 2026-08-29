import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel
import "extensions/currency" as CurrencyExtension

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string pluginPath: root.manifest && root.manifest.__sourceDir ? String(root.manifest.__sourceDir) : ""
  property var shell: null
  property var manifest: null

  // Plugin lifecycle hooks. The host calls open(payloadJson) after
  // `omarchy-shell shell summon quantumfire.omalaunch ...` and close() when hidden.
  property string pendingInitialMenu: "root"

  function open(payloadJson) {
    root.loadExtensions()
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    if (payload.mode === "select" || payload.mode === "input") {
      root.openDmenu(payload)
    } else {
      root.openRoute(payload.initialMenu || payload.menu || "root")
    }
  }

  function close() {
    root.cancel()
  }

  function refresh() {
    defaultMenuFile.reload()
    userMenuFile.reload()
    root.loadExtensions()
    return "ok"
  }

  function ping() { return "ok" }

  property string fontFamily: Style.font.menuFamily
  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  property var defaultMenuItems: []
  property var userMenuItems: []
  property var extensions: []
  property var extensionDiagnostics: []
  property var unavailableResultExtension: null
  property bool extensionsReloadPending: false
  property bool opened: false
  property string mode: "menu"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property string selectionFile: ""
  property string doneFile: ""
  property int dmenuWidth: 300
  property int dmenuMaxHeight: 0
  property bool requestActive: false
  property bool rowsLoaded: false
  property string activeMenu: "root"
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property var resultQueue: []
  readonly property int maxProcessOutputBytes: 1024 * 1024
  property var items: ({})
  property var itemOrder: []
  property var searchExcludedRoots: ["setup.default"]
  property var navStack: []
  property var providersLoaded: ({})
  property var providerQueue: []
  property int providerRevision: 0
  property string extensionQuery: ""
  property string extensionResult: ""
  property var resultExtension: null
  property int extensionQuerySerial: 0
  property bool fileBrowserActive: false
  property var fileBrowserExtension: null
  property string fileBrowserPath: ""
  property var fileEntries: []
  property int fileScanSerial: 0
  property string fileCopyFeedbackPath: ""
  property string fileCopyFeedback: ""
  property bool actionPanelActive: false
  property var actionPanelFile: null
  readonly property var selectedFileRow: root.fileBrowserActive && !root.actionPanelActive && root.cursorActive
    && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count
    ? displayModel.get(root.selectedIndex) : null
  readonly property string selectedFilePath: root.selectedFileRow ? String(root.selectedFileRow.action || "") : ""
  readonly property bool imagePreviewActive: MenuModel.isImagePath(root.selectedFilePath)
  readonly property int previewPaneWidth: Style.space(280)

  // Shared application engine (entries, hidden filters, icons, launch,
  // removal), owned by the shell and also used by the standalone launcher.
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  property bool deleteConfirmOpen: false
  property string pendingStarSelectionId: ""
  property var deleteTarget: null
  onOpenedChanged: if (!opened) { deleteConfirmOpen = false; deleteTarget = null }
  // Bound to the central [menu] section in shell.toml via Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  LauncherFavorites { id: favorites }
  LauncherUsage { id: usage }
  CurrencyExtension.CurrencyRates { id: currencyRates }

  Connections {
    target: currencyRates
    function onRefreshed() {
      if (!root.resultExtension || root.resultExtension.capability !== "currency") return
      root.extensionQuerySerial += 1
      extensionQueryTimer.restart()
    }
  }

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property real rowReservedBorderLeft: Border.left(selectedBorderSpec)
  readonly property real rowReservedBorderRight: Border.right(selectedBorderSpec)
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int baseRowHeight: Math.max(Style.space(50), Style.font.body + Style.spacing.rowPaddingX * 2)
  property int detailRowHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  // How much of the first hidden row stays visible at the fold — enough to
  // read as a cut-off row rather than a bottom border.
  property int rowPeek: Math.round(baseRowHeight * 0.55)
  property int rowSpacing: Style.spacing.xs
  property int dividerHeight: Style.space(17)
  property bool searchDivider: false
  property int layoutSerial: 0
  property int cardWidth: Math.min(root.dmenuActive
    ? Style.space(root.dmenuWidth)
    : Style.space(root.imagePreviewActive ? 900 : 600), panel.width - Style.gapsOut * 2)
  readonly property bool emptyRoot: !root.dmenuActive && root.activeMenu === "root" && !root.filterText && displayModel.count === 0
  // The overlay can report the compact card's height instead of the output
  // size, especially on scaled displays. Never let that become the ceiling.
  readonly property int overlayHeight: {
    var h = Math.max(0, panel.height)
    if (panel.screen && panel.screen.height > h) h = panel.screen.height
    return Math.max(h, 720)
  }
  // Dummy geometry reads keep this binding honest: rowListHeight() also
  // looks at panel size and the frozen top, which are not otherwise deps.
  property int visibleRowsHeight: {
    var _geometry = root.overlayHeight + panel.cardTop
    if (root.emptyRoot) return 0
    var computed = root.dmenuActive
      ? dmenuRowListHeight(layoutSerial + _geometry, displayModel.count, filterText)
      : rowListHeight(layoutSerial + _geometry, displayModel.count, filterText, searchDivider)
    if (displayModel.count > 1) return Math.max(computed, root.baseRowHeight * 8)
    return computed
  }
  property int cardHeight: {
    var wanted = contentMargin * 2 + headerHeight
    if (root.dmenuActive) {
      if (mode !== "input") wanted += contentSpacing + visibleRowsHeight
    } else if (visibleRowsHeight > 0) {
      wanted += contentSpacing + visibleRowsHeight
    }
    return Math.min(wanted, root.overlayHeight - Style.gapsOut * 2)
  }

  function finishRequest(selection) {
    if (!root.requestActive || !root.doneFile) {
      root.opened = false
      return
    }

    var completion = {
      requestId: root.requestSerial,
      selectionFile: root.selectionFile,
      doneFile: root.doneFile,
      selection: selection
    }
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""
    root.resultQueue = root.resultQueue.concat([completion])
    root.startResultWrite()
  }

  // Completion files are a protocol: every accepted request must produce its
  // own done file. Serialize writes so a quick second request cannot replace
  // the command of a Process that is still completing the first one.
  function startResultWrite() {
    if (resultProc.running || root.resultQueue.length === 0) return
    var completion = root.resultQueue[0]
    root.resultQueue = root.resultQueue.slice(1)
    resultProc.requestId = completion.requestId
    if (completion.selection === null || completion.selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(completion.doneFile)]
    } else if (completion.selectionFile) {
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(completion.selection) + " > " + Util.shellQuote(completion.selectionFile) + "; : > " + Util.shellQuote(completion.doneFile)]
    } else {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(completion.doneFile)]
    }
    resultProc.running = true
  }

  function collectBounded(proc, data) {
    if (proc.outputOverflow) return
    var next = proc.collected + data + "\n"
    if (next.length > root.maxProcessOutputBytes) {
      proc.outputOverflow = true
      proc.collected = ""
      proc.running = false
      return
    }
    proc.collected = next
  }

  function runAction(action) {
    var command = String(action || "")
    if (!command) return

    Util.execDetached(command)
  }

  // Menu rows only surface their detail while a search is narrowing them;
  // dmenu rows carry caller-supplied subtext that must always be visible.
  function rowHeightForDetail(detail) {
    return (root.filterText || root.dmenuActive) && detail ? root.detailRowHeight : root.baseRowHeight
  }

  // Height the card can devote to rows before running off the screen — or
  // past the frozen top edge once a search has pinned the card in place.
  // Uses panel.cardTop rather than effectiveCardTop: the centered top is
  // derived from the card height, which this value feeds.
  function availableRowsHeight() {
    var screenH = root.overlayHeight
    var top = panel.cardTop >= 0 ? panel.cardTop : Style.gapsOut
    var available = screenH - top - Style.gapsOut - root.contentMargin * 2 - root.headerHeight - root.contentSpacing
    return Math.max(root.baseRowHeight, Math.min(available, Math.round(screenH * 0.5)))
  }

  // When every row fits, the list gets its full height. When they don't,
  // the card must end mid-row: a clipped row is what tells the eye there is
  // more below the fold, so never come out even on a row boundary.
  function foldedListHeight(totals, available) {
    var count = totals.length
    if (count === 0) return root.baseRowHeight
    if (totals[count - 1] <= available) return totals[count - 1]

    var peek = root.rowPeek
    var full = 0
    while (full < count && totals[full] <= available) full++
    while (full > 1 && totals[full - 1] + root.rowSpacing + peek > available) full--
    if (full < 1) return Math.max(available, root.baseRowHeight)

    return totals[full - 1] + root.rowSpacing + peek
  }

  function rowListHeight(_serial, _count, _filter, _divider) {
    var n = displayModel.count
    if (n <= 0) return root.baseRowHeight

    var rowH = (root.filterText || root.dmenuActive) ? root.detailRowHeight : root.baseRowHeight
    var total = n * rowH + Math.max(0, n - 1) * root.rowSpacing
    if (_divider) total += root.dividerHeight

    var available = availableRowsHeight()
    var floorN = Math.min(n, 8)
    var floor = floorN * rowH + Math.max(0, floorN - 1) * root.rowSpacing
    if (total <= available) return Math.max(total, floor)

    var peek = root.rowPeek
    var full = 1
    while (full < n && full * rowH + (full - 1) * root.rowSpacing + peek <= available) full++
    if (full > 1 && (full - 1) * rowH + (full - 2) * root.rowSpacing + peek > available) full--
    var folded = Math.max(rowH, (full - 1) * rowH + Math.max(0, full - 2) * root.rowSpacing + peek)
    return Math.max(folded, floor)
  }

  function dmenuRowListHeight(_serial, _count, _filter) {
    if (root.mode === "input") return 0
    if (displayModel.count === 0) return root.baseRowHeight

    var available = availableRowsHeight()
    if (root.dmenuMaxHeight > 0) available = Math.min(available, Style.space(root.dmenuMaxHeight))

    var totals = []
    var total = 0
    for (var i = 0; i < displayModel.count; i++) {
      if (i > 0) total += root.rowSpacing
      total += root.rowHeightForDetail(displayModel.get(i).detail)
      totals.push(total)
    }

    return foldedListHeight(totals, available)
  }

  function item(id) {
    return root.items[id] || null
  }

  // ------------------------------------------------------------------
  // JSONC → normalized item array. Mirrors the bash bin's jq pipeline so
  // the on-disk authoring format stays untouched.
  // ------------------------------------------------------------------

  function stripJsonc(raw) {
    return MenuModel.stripJsonc(raw)
  }

  function normalizeAliases(value) {
    return MenuModel.normalizeAliases(value)
  }

  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }

  function commandArguments(command, replacements) {
    var parts = []
    for (var i = 0; i < command.length; i++) {
      var argument = String(command[i])
      for (var key in replacements)
        argument = argument.replace(new RegExp("\\{" + key + "\\}", "g"), String(replacements[key]))
      parts.push(argument)
    }
    return parts
  }

  function shellCommand(command, replacements) {
    var arguments = root.commandArguments(command, replacements)
    var parts = []
    for (var i = 0; i < arguments.length; i++) parts.push(root.shellQuote(arguments[i]))
    return parts.join(" ")
  }

  function extensionAction(extension, prompt) {
    return root.shellCommand(extension.command, { prompt: prompt })
  }

  function loadExtensions() {
    if (extensionProc.running) {
      root.extensionsReloadPending = true
      return
    }
    root.extensionsReloadPending = false
    extensionProc.collected = ""
    extensionProc.outputOverflow = false
    var script = "emit_extension() { "
      + "local file=$1 bundled=$2 raw requirement missing_json source_dir; local -a missing=(); source_dir=${file%/*}; "
      + "raw=$(jq -c '.' \"$file\" 2>/dev/null) || return; "
      + "while IFS= read -r requirement; do [[ -z $requirement ]] || command -v \"$requirement\" &>/dev/null || missing+=(\"$requirement\"); done < <(jq -r '.requires[]? // empty' <<<\"$raw\"); "
      + "missing_json=$(printf '%s\\n' \"${missing[@]}\" | jq -Rsc 'split(\"\\n\") | map(select(length > 0))'); "
      + "jq -c --argjson bundled \"$bundled\" --argjson missing \"$missing_json\" --arg sourceDir \"$source_dir\" '. + {_bundled:$bundled,_missingRequires:$missing,_sourceDir:$sourceDir}' <<<\"$raw\"; "
      + "}; { shopt -s nullglob; "
      + "for bundled in " + root.shellQuote(root.pluginPath) + "/extensions/*/extension.json; do emit_extension \"$bundled\" true; done; "
      + "declare -A enabled=(); "
      + "while IFS= read -r id; do enabled[\"$id\"]=1; done < <(omarchy plugin list --json | jq -r '.[] | select(.enabled == true) | .id'); "
      + "shopt -s nullglob; "
      + "for manifest in " + root.shellQuote(root.omarchyPath) + "/shell/plugins/*/manifest.json \"$HOME\"/.config/omarchy/plugins/*/manifest.json; do "
      + "id=$(jq -r '.id // empty' \"$manifest\" 2>/dev/null); [[ $id && ${enabled[$id]+yes} ]] || continue; "
      + "dir=${manifest%/manifest.json}; "
      + "while IFS= read -r provider; do "
      + "[[ $provider && $provider != /* && $provider != *..* ]] || continue; "
      + "file=$dir/$provider; [[ -f $file ]] && emit_extension \"$file\" false; "
      + "done < <(jq -r '((.omalaunch.extensions // []) + (.omalaunch.queryProviders // []))[]? // empty' \"$manifest\" 2>/dev/null); "
      + "done; } | jq -s '.'"
    extensionProc.command = ["bash", "-lc", script]
    extensionProc.running = true
  }

  function isPotentialExtensionQuery(value) {
    var query = String(value || "")
    return /^\s*[+-]?(?:\d|\.\d)/.test(query)
      || MenuModel.queryExtension(root.extensions, query) !== null
      || MenuModel.unavailableQueryExtension(root.extensions, query) !== null
  }

  function scheduleExtensionQuery() {
    root.extensionQuerySerial += 1
    root.extensionQuery = ""
    root.extensionResult = ""
    root.resultExtension = null
    root.unavailableResultExtension = null
    extensionQueryTimer.stop()
    if (extensionQueryProc.running) extensionQueryProc.running = false
    if (root.dmenuActive) return

    var query = root.filterText.trim()
    root.resultExtension = MenuModel.queryExtension(root.extensions, query)
    root.unavailableResultExtension = MenuModel.unavailableQueryExtension(root.extensions, query)
    if (root.resultExtension) extensionQueryTimer.start()
  }

  function extensionById(id) {
    for (var i = 0; i < root.extensions.length; i++)
      if (root.extensions[i].id === id) return root.extensions[i]
    return null
  }

  function enterFileBrowser(extension) {
    if (!extension || !extension.available) return
    root.fileBrowserActive = true
    root.fileBrowserExtension = extension
    root.fileBrowserPath = extension.root === "~" ? Quickshell.env("HOME") : extension.root
    root.filterText = ""
    root.fileEntries = []
    root.selectedIndex = 0
    root.cursorActive = true
    root.scheduleFileScan()
  }

  function leaveFileBrowser() {
    root.actionPanelActive = false
    root.actionPanelFile = null
    root.fileBrowserActive = false
    root.fileBrowserExtension = null
    root.fileBrowserPath = ""
    root.fileEntries = []
    root.filterText = ""
    root.rebuildDisplay()
  }

  function parentPath(path) {
    var value = String(path || "").replace(/\/+$/, "")
    if (!value || value === "/") return "/"
    var slash = value.lastIndexOf("/")
    return slash <= 0 ? "/" : value.substring(0, slash)
  }

  function scheduleFileScan() {
    root.fileScanSerial += 1
    fileScanTimer.restart()
    if (fileScanProc.running) fileScanProc.running = false
  }

  function rebuildFileDisplay() {
    displayModel.clear()
    root.searchDivider = false
    for (var i = 0; i < root.fileEntries.length; i++) {
      var entry = root.fileEntries[i]
      var isDirectory = entry.type === "directory"
      var feedback = entry.path === root.fileCopyFeedbackPath ? root.fileCopyFeedback : ""
      var description = feedback || (isDirectory ? entry.path : entry.path + "  ·  Ctrl+C to copy path")
      var item = root.normalizeItem("file." + (isDirectory ? "directory." : "item.") + i, {
        icon: feedback.indexOf("Copied") === 0 ? "✓" : (isDirectory ? "󰉋" : "󰈔"),
        label: entry.name,
        description: description,
        action: entry.path
      })
      var row = root.displayRow(item, item.description, i)
      row.starred = false
      displayModel.append(row)
    }
    root.layoutSerial += 1
    if (displayModel.count === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= displayModel.count) root.selectedIndex = displayModel.count - 1
    Qt.callLater(function() { if (displayModel.count > 0) root.revealCursor() })
  }

  function rebuildActionPanel() {
    displayModel.clear()
    if (!root.actionPanelFile || !root.fileBrowserExtension) return
    var actions = root.actionPanelFile.type === "directory"
      ? [
          { id: "open-files", icon: "󰉋", label: "Open in Files" },
          { id: "open-terminal", icon: "", label: "Open in terminal" }
        ]
      : [{ id: "open", icon: "󰈔", label: "Open" }]
    actions = actions.concat([
      { id: "copy-path", icon: "󰆏", label: "Copy path" },
      { id: "copy-file", icon: "󰆏", label: "Copy file to clipboard" }
    ])
    for (var i = 0; i < actions.length; i++) {
      var action = actions[i]
      var item = root.normalizeItem("file.action." + action.id, {
        icon: action.icon,
        label: action.label,
        description: root.actionPanelFile.path,
        action: action.id
      })
      var row = root.displayRow(item, root.actionPanelFile.path, i)
      row.starred = false
      displayModel.append(row)
    }
    root.layoutSerial += 1
    root.selectedIndex = 0
    root.cursorActive = true
    Qt.callLater(function() { root.revealCursor() })
  }

  function openActionPanel() {
    if (!root.fileBrowserActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.itemId.indexOf("file.") !== 0 || row.itemId.indexOf("file.action.") === 0) return
    root.actionPanelFile = {
      index: root.selectedIndex,
      path: row.action,
      name: row.label,
      type: row.itemId.indexOf("file.directory.") === 0 ? "directory" : "file"
    }
    root.actionPanelActive = true
    root.rebuildActionPanel()
  }

  function closeActionPanel() {
    var previousIndex = root.actionPanelFile ? root.actionPanelFile.index : 0
    root.actionPanelActive = false
    root.actionPanelFile = null
    root.selectedIndex = previousIndex
    root.rebuildFileDisplay()
  }

  function startFileCopy(path, command, successMessage) {
    if (!path || !command || command.length === 0 || fileCopyProc.running) return
    fileCopyProc.copyPath = path
    fileCopyProc.successMessage = successMessage
    fileCopyProc.command = root.commandArguments(command, { path: path })
    fileCopyProc.running = true
  }

  function copySelectedFilePath() {
    if (!root.fileBrowserActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || !root.fileBrowserExtension) return
    root.startFileCopy(row.action, root.fileBrowserExtension.copyCommand, "Copied path")
  }

  function activateFileAction(action) {
    if (!root.actionPanelFile || !root.fileBrowserExtension) return
    var path = root.actionPanelFile.path
    if (action === "copy-path" || action === "copy-file") {
      var command = action === "copy-path" ? root.fileBrowserExtension.copyCommand : root.fileBrowserExtension.copyFileCommand
      var message = action === "copy-path" ? "Copied path" : "Copied file"
      root.closeActionPanel()
      root.startFileCopy(path, command, message)
      return
    }

    var commandToRun = action === "open-terminal"
      ? root.fileBrowserExtension.terminalCommand
      : (action === "open-files" ? root.fileBrowserExtension.directoryCommand : root.fileBrowserExtension.command)
    var shellAction = root.shellCommand(commandToRun, { path: path })
    root.actionPanelActive = false
    root.fileBrowserActive = false
    root.opened = false
    root.runAction(shellAction)
  }

  function normalizeItem(id, raw) {
    return MenuModel.normalizeItem(id, raw)
  }

  function parseMenuJsonc(raw) {
    return MenuModel.parseMenuJsonc(raw)
  }

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  function rebuildItemsFromSources() {
    var mergedMenu = MenuModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
    root.providerRevision += 1
    root.providersLoaded = ({})
    root.providerQueue = []
    var nextItems = Object.assign({}, mergedMenu.items)
    nextItems.omarchy = root.normalizeItem("omarchy", {
      icon: "",
      iconFont: "omarchy",
      label: "Omarchy",
      title: "Omarchy"
    })
    for (var id in nextItems) {
      if (id === "root" || id === "omarchy") continue
      if (nextItems[id].parent === "root") nextItems[id] = Object.assign({}, nextItems[id], { parent: "omarchy" })
    }
    var nextOrder = mergedMenu.itemOrder.filter(function(id) { return id !== "omarchy" })
    var rootIndex = nextOrder.indexOf("root")
    nextOrder.splice(rootIndex >= 0 ? rootIndex + 1 : 0, 0, "omarchy")
    root.items = nextItems
    root.itemOrder = nextOrder
    root.rowsLoaded = true
    root.evaluateGuards()
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim()) root.loadProvidersForSearch()
        else root.loadProviderForMenu(root.activeMenu)
      }
    }
  }

  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`. A `volatile` provider
  // re-runs every time its submenu is entered, so a font installed since the
  // shell started shows up without restarting it.
  readonly property var providers: ({
    "fonts": {
      script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "",
      volatile: true,
      actionFor: function(value) { return "omarchy-font-set " + Util.shellQuote(value) }
    },
    "power-profiles": {
      script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      actionFor: function(value) { return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(value) }
    }
  })

  function slugify(value) {
    return MenuModel.slugify(value)
  }

  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  function mergeAppRows() {
    if (!root.appLibrary) return

    var rows = root.appLibrary.sortedEntries("")
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue
      var subtext = root.appLibrary.entrySubtext(entry)
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
      } catch (e) { }
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: root.appLibrary.entryName(entry),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        when: "",
        checked: "",
        order: 0
      })
    }

    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
    if (entry.provider === "apps") {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    var spec = root.providers[entry.provider]
    if (!spec) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.revision = root.providerRevision
    providerProc.collected = ""
    providerProc.outputOverflow = false
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec) return
    var lines = String(rows || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      var label = parts[0] || ""
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label) continue
      // Distinct values can slugify alike — Fira Code and Fira-Code both give
      // fira-code — and a repeated id is dropped, which would silently lose a
      // row from the list. Nudge it until it is the row's own.
      var rowId = menuId + "." + root.slugify(value)
      while (takenIds[rowId]) rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        when: "",
        checked: "",
        order: 0
      })
    }
    var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  // Entering a submenu is the one moment a volatile list is worth paying for
  // again: it may have been reshaped by the last pick from it. Search doesn't
  // invalidate, or every keystroke would restart the same enumeration.
  function invalidateVolatileProvider(id) {
    var entry = root.item(id)
    var spec = entry && entry.provider ? root.providers[entry.provider] : null
    if (spec && spec.volatile) root.providersLoaded[id] = false
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    // Native providers don't touch providerProc, so they never need to queue.
    if (entry.provider === "apps") {
      root.startProviderForMenu(id)
      return
    }

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  function depthFor(id) {
    return MenuModel.depthFor(root.items, id)
  }

  function pathFor(id) {
    return MenuModel.pathFor(root.items, id)
  }

  function parentPathFor(id) {
    return MenuModel.parentPathFor(root.items, id)
  }

  function isDescendantOf(id, ancestorId) {
    return MenuModel.isDescendantOf(root.items, id, ancestorId)
  }

  function childCount(id) {
    return MenuModel.childCount(root.items, root.itemOrder, id)
  }

  // Guarded items are hidden when their `when:` evaluates false. Static
  // submenus are also hidden when none of their descendants are visible;
  // provider-backed menus stay visible because their rows load on demand.
  function isVisible(entry) {
    return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
  }

  // Label with the ✓ marker baked in when `checked:` evaluated truthy.
  function labelFor(entry) {
    return MenuModel.labelFor(entry, root.checkedResults)
  }

  function searchableToken(value) {
    return MenuModel.searchableToken(value)
  }

  function leafIdFor(id) {
    return MenuModel.leafIdFor(id)
  }

  function nameSearchText(entry) {
    return MenuModel.nameSearchText(entry)
  }

  function termInSearchWords(term, text) {
    return MenuModel.termInSearchWords(term, text)
  }

  function descriptionTextMatches(query, text) {
    return MenuModel.descriptionTextMatches(query, text)
  }

  function matchesQuery(entry, query) {
    return MenuModel.matchesQuery(entry, query, root.isVisible(entry))
  }

  function searchScore(entry, query) {
    return MenuModel.searchScore(root.items, entry, query)
  }

  function displayRow(entry, detail, score, section) {
    return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, entry, detail, score, section)
  }

  function rebuildDmenuDisplay() {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      return
    }

    var query = root.filterText.trim().toLowerCase()
    for (var i = 0; i < root.dmenuOptions.length; i++) {
      // An option is "<label>", "<glyph>\t<label>", or
      // "<glyph>\t<label>\t<subtext>". The glyph never comes back with the
      // selection; the subtext renders under the label, filters alongside it,
      // and returns with the selection as a stable key for same-named rows.
      var parts = String(root.dmenuOptions[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (query && label.toLowerCase().indexOf(query) < 0
          && detail.toLowerCase().indexOf(query) < 0) continue
      displayModel.append({
        itemId: "dmenu." + i,
        kind: "dmenu",
        icon: icon,
        iconFont: "",
        appIcon: "",
        appId: "",
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: "",
        starred: false
      })
    }

    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  function rebuildDisplay() {
    if (root.actionPanelActive) {
      root.rebuildActionPanel()
      return
    }
    if (root.fileBrowserActive) {
      root.rebuildFileDisplay()
      return
    }
    if (root.dmenuActive) {
      root.rebuildDmenuDisplay()
      return
    }

    displayModel.clear()

    if (!root.rowsLoaded) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (query) {
      var liveResult = root.extensionQuery === query ? root.extensionResult : ""
      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (MenuModel.isSearchExcluded(root.items, entry.id, root.searchExcludedRoots)) continue
        if (!root.isDescendantOf(entry.id, active)) continue
        if (!root.matchesQuery(entry, query)) continue

        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
        row.starred = favorites.isStarred(row.itemId)
        row.matchPriority = MenuModel.searchMatchPriority(entry, query)
        row.usageCount = usage.count(row.itemId)
        row.lastUsedAt = usage.lastUsedAt(row.itemId)
        rows.push(row)
      }

      rows.sort(function(a, b) {
        return MenuModel.compareSearchRows(a, b, query.length >= 3)
      })

      var extensionSuggestions = MenuModel.suggestExtensions(root.extensions, query)
      for (var suggestionIndex = extensionSuggestions.length - 1; suggestionIndex >= 0; suggestionIndex--) {
        var suggestion = extensionSuggestions[suggestionIndex]
        var suggestedExtension = suggestion.extension
        var suggestionDetail = suggestedExtension.available
          ? suggestedExtension.description
          : "Missing dependency: " + suggestedExtension.missingRequires.join(", ")
        var suggestionId = suggestedExtension.available ? "extension.prepare." : "extension.unavailable."
        var suggestionItem = root.normalizeItem(suggestionId + suggestedExtension.id, {
          icon: suggestedExtension.icon,
          iconFont: suggestedExtension.iconFont,
          label: suggestedExtension.label,
          description: suggestionDetail,
          action: suggestedExtension.available ? suggestion.prefix + " " : ""
        })
        rows.unshift(root.displayRow(suggestionItem, suggestionDetail, -3))
      }

      var extensionMatches = MenuModel.matchExtensions(root.extensions, query)
      for (var extensionIndex = extensionMatches.length - 1; extensionIndex >= 0; extensionIndex--) {
        var extensionMatch = extensionMatches[extensionIndex]
        var extension = extensionMatch.extension
        var extensionDetail = extension.available
          ? extension.description
          : "Missing dependency: " + extension.missingRequires.join(", ")
        var extensionId = extension.available ? "extension." : "extension.unavailable."
        var extensionItem = root.normalizeItem(extensionId + extension.id, {
          icon: extension.icon,
          iconFont: extension.iconFont,
          label: extension.label + ": " + extensionMatch.prompt,
          description: extensionDetail,
          action: extension.available ? root.extensionAction(extension, extensionMatch.prompt) : ""
        })
        rows.unshift(root.displayRow(extensionItem, extensionDetail, -2))
      }

      if (root.unavailableResultExtension) {
        var unavailableDetail = "Missing dependency: " + root.unavailableResultExtension.missingRequires.join(", ")
        var unavailableItem = root.normalizeItem("extension.unavailable." + root.unavailableResultExtension.id, {
          icon: root.unavailableResultExtension.icon,
          iconFont: root.unavailableResultExtension.iconFont,
          label: root.unavailableResultExtension.label + " unavailable",
          description: unavailableDetail
        })
        rows.unshift(root.displayRow(unavailableItem, unavailableDetail, -1))
      }

      if (liveResult && root.resultExtension) {
        var resultItem = root.normalizeItem("extension.result", {
          icon: root.resultExtension.icon,
          iconFont: root.resultExtension.iconFont,
          label: "= " + liveResult,
          description: root.resultExtension.description,
          action: root.shellCommand(root.resultExtension.resultCommand, { result: liveResult, query: query })
        })
        rows.unshift(root.displayRow(resultItem, root.resultExtension.description, -1))
      }
    } else {
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.id === "root") continue
        if (active === "root") {
          if (child.id !== "omarchy" && !favorites.isStarred(child.id)) continue
        } else if (child.parent !== active) continue
        if (!root.isVisible(child)) continue
        var childDetail = active === "root" ? root.parentPathFor(child.id) : child.description
        var childRow = root.displayRow(child, childDetail, child.order)
        childRow.starred = favorites.isStarred(childRow.itemId)
        rows.push(childRow)
      }

      if (active === "root") {
        rows.sort(function(a, b) {
          if (a.itemId === "omarchy" || b.itemId === "omarchy") return a.itemId === "omarchy" ? -1 : 1
          var aLabel = String(a.label || "").toLowerCase()
          var bLabel = String(b.label || "").toLowerCase()
          if (aLabel < bLabel) return -1
          if (aLabel > bLabel) return 1
          return String(a.itemId || "").localeCompare(String(b.itemId || ""))
        })
      }

      // DesktopEntries can reorder its values when an application starts.
      // Keep the Apps menu alphabetical independently of provider refreshes.
      if (active === "apps") {
        rows.sort(function(a, b) {
          var aLabel = String(a.label || "").toLowerCase()
          var bLabel = String(b.label || "").toLowerCase()
          if (aLabel < bLabel) return -1
          if (aLabel > bLabel) return 1
          var aId = String(a.itemId || "")
          var bId = String(b.itemId || "")
          if (aId < bId) return -1
          if (aId > bId) return 1
          return 0
        })
      }
    }

    for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // Contain alone parks the cursor row flush with the viewport edge, hiding
  // the neighbor entirely and losing the fold affordance. Keep the next
  // hidden row peeking past the cursor in the direction of travel.
  function revealCursor() {
    if (displayModel.count === 0) return
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)

    var item = resultList.itemAtIndex(root.selectedIndex)
    if (!item) return

    var reach = root.rowPeek + root.rowSpacing
    if (root.selectedIndex < displayModel.count - 1) {
      var maxY = Math.max(resultList.originY, resultList.originY + resultList.contentHeight - resultList.height)
      var overhang = item.y + item.height + reach - (resultList.contentY + resultList.height)
      if (overhang > 0) resultList.contentY = Math.min(resultList.contentY + overhang, maxY)
    }
    if (root.selectedIndex > 0) {
      var underhang = resultList.contentY - (item.y - reach)
      if (underhang > 0) resultList.contentY = Math.max(resultList.contentY - underhang, resultList.originY)
    }
  }

  function select(delta) {
    if (displayModel.count === 0) return

    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    revealCursor()
  }

  function setFilter(nextFilter) {
    if (root.actionPanelActive) return
    panel.freezeCardTop()
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = root.mode !== "input"
    root.disarmPointer()
    if (root.fileBrowserActive) {
      root.rebuildFileDisplay()
      root.scheduleFileScan()
      return
    }
    if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
    root.scheduleExtensionQuery()
  }

  function setActiveMenu(id, pushHistory, fromPointer) {
    panel.freezeCardTop()
    if (!root.item(id)) id = "root"
    if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (fromPointer) pointerGate.allowInitialSample()
    else root.disarmPointer()
    root.rebuildDisplay()
    root.invalidateVolatileProvider(id)
    root.loadProviderForMenu(id)
  }

  function goBack() {
    if (root.activeMenu === "root") return false

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false)
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
    return true
  }

  function activateIndex(index, fromPointer) {
    if (root.deleteConfirmOpen) return
    if (root.dmenuActive) {
      if (root.mode === "input") {
        root.applyDmenuSelection(root.filterText)
        return
      }
      if (index < 0 || index >= displayModel.count) return
      var picked = displayModel.get(index)
      root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
      return
    }

    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    if (root.actionPanelActive && row.itemId.indexOf("file.action.") === 0) {
      root.activateFileAction(row.action)
      return
    }
    if (row.itemId.indexOf("extension.unavailable.") === 0) return
    if (row.itemId.indexOf("extension.prepare.") === 0) {
      var preparedExtension = root.extensionById(row.itemId.substring("extension.prepare.".length))
      if (preparedExtension && preparedExtension.mode === "files") root.enterFileBrowser(preparedExtension)
      else root.setFilter(row.action)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      return
    }
    if (root.fileBrowserActive && row.itemId.indexOf("file.") === 0) {
      if (row.itemId.indexOf("file.directory.") === 0) {
        root.fileBrowserPath = row.action
        root.filterText = ""
        root.fileEntries = []
        root.selectedIndex = 0
        root.scheduleFileScan()
      } else {
        var openCommand = root.shellCommand(root.fileBrowserExtension.command, { path: row.action })
        root.fileBrowserActive = false
        root.fileBrowserExtension = null
        root.applySerial = root.requestSerial
        root.opened = false
        root.runAction(openCommand)
      }
      return
    }
    if (row.itemId !== "extension.result") usage.record(row.itemId)
    if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true, fromPointer)
    } else if (row.kind === "app") {
      var appId = row.appId
      var label = row.label
      applySerial = requestSerial
      opened = false
      filterText = ""
      if (root.appLibrary) root.appLibrary.launch(appId, label)
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  function toggleSelectedStar() {
    if (root.dmenuActive || root.fileBrowserActive || !root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.itemId === "omarchy" || row.itemId === "extension.result" || !favorites.loaded) return
    root.pendingStarSelectionId = row.itemId
    favorites.toggle(row.itemId)
  }

  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "app") return
    root.deleteTarget = { appId: row.appId, label: row.label }
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    deleteConfirm.selectedIndex = 1
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (!target) return
    root.cancel()
    if (root.appLibrary) root.appLibrary.remove(target.appId, target.label)
  }

  function applyDmenuSelection(value) {
    applySerial = requestSerial
    opened = false
    filterText = ""
    root.finishRequest(value)
  }

  function applySelected(id, action) {
    if (!id) { cancel(); return }

    applySerial = requestSerial
    opened = false
    filterText = ""
    root.runAction(action)
  }

  function cancel() {
    if (root.dmenuActive) root.finishRequest(null)
    root.actionPanelActive = false
    root.actionPanelFile = null
    root.fileBrowserActive = false
    root.fileBrowserExtension = null
    root.fileBrowserPath = ""
    root.fileEntries = []
    opened = false
    filterText = ""
  }

  function openExistingMenu(initialMenu) {
    requestSerial += 1
    mode = "menu"
    requestActive = false
    selectionFile = ""
    doneFile = ""
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = true
    root.disarmPointer()
    root.evaluateGuards()
    opened = true
    rebuildDisplay()
    invalidateVolatileProvider(activeMenu)
    loadProviderForMenu(activeMenu)
    if (activeMenu === "root") root.loadProviderForMenu("apps")
    // The shell may start before first-install packages have finished placing
    // their icons. Refresh here even when the desktop entry list did not change.
    if (root.appLibrary) root.appLibrary.refreshIcons()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openDmenu(payload) {
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = mode !== "input"
    root.disarmPointer()
    opened = true
    rebuildDisplay()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  ListModel { id: displayModel }

  // ----------------------------------------------------------- route surface
  //
  // The menu is opened through the standard plugin lifecycle:
  // `omarchy-shell shell summon quantumfire.omalaunch '{"menu":"system"}'`.
  // Callers may pass a real id (`system`, `setup.power`) or an alias declared
  // in JSONC (`power`, `reminder-set`). Unknown strings fall through to the
  // id-as-route behavior so misspellings still attempt to open the literal id.
  function resolveRoute(input) {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }

  function openRoute(initialMenu) {
    var id = root.resolveRoute(initialMenu)
    var entry = root.items[id]
    // If the resolved id is an action (i.e. the user invoked an alias for
    // a leaf, e.g. `omarchy menu summon screenrecord-stop`), run it directly
    // instead of opening an action with no children.
    if (entry && entry.kind === "action" && entry.action) {
      root.cancel()
      root.runAction(entry.action)
      return "ok"
    }
    // If it's a link (a redirect to another menu), follow the link.
    if (entry && entry.kind === "link" && entry.target) id = entry.target
    root.pendingInitialMenu = id
    root.openExistingMenu(id)
    return "ok"
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  Timer {
    id: fileCopyFeedbackTimer
    interval: 1600
    repeat: false
    onTriggered: {
      root.fileCopyFeedbackPath = ""
      root.fileCopyFeedback = ""
      if (root.fileBrowserActive) root.rebuildFileDisplay()
    }
  }

  Process {
    id: fileCopyProc
    property string copyPath: ""
    property string successMessage: "Copied path"
    onExited: function(exitCode) {
      root.fileCopyFeedbackPath = fileCopyProc.copyPath
      root.fileCopyFeedback = exitCode === 0 ? fileCopyProc.successMessage : "Copy failed"
      if (root.fileBrowserActive) root.rebuildFileDisplay()
      fileCopyFeedbackTimer.restart()
    }
  }

  Timer {
    id: fileScanTimer
    interval: 120
    repeat: false
    onTriggered: {
      if (!root.fileBrowserActive || !root.fileBrowserPath) return
      var base = root.fileBrowserPath
      var needle = root.filterText.trim()
      var sourceCommand = needle
        ? "fd --color never --absolute-path --print0 --type file --type directory . \"$base\" 2>/dev/null | fzf --read0 --print0 --filter=\"$needle\" --scheme=path --tiebreak=begin,length --no-multi-line"
        : "fd --color never --absolute-path --print0 --type file --type directory --max-depth 1 . \"$base\" 2>/dev/null -X stat --printf '%Y\\t%n\\0' | sort -z -t $'\\t' -k1,1nr"
      var script = "base=" + root.shellQuote(base) + "; needle=" + root.shellQuote(needle) + "; count=0; "
        + "while IFS= read -r -d '' entry && (( count < 100 )); do "
        + "[[ -n $needle ]] || entry=${entry#*$'\\t'}; clean=${entry%/}; [[ -d $clean ]] && type=directory || type=file; name=${clean##*/}; "
        + "jq -cn --arg path \"$clean\" --arg name \"$name\" --arg type \"$type\" '{path:$path,name:$name,type:$type}'; "
        + "count=$((count + 1)); done < <(" + sourceCommand + ")"
      fileScanProc.revision = root.fileScanSerial
      fileScanProc.scanPath = base
      fileScanProc.query = needle
      fileScanProc.collected = ""
      fileScanProc.command = ["bash", "-lc", script]
      fileScanProc.running = true
    }
  }

  Process {
    id: fileScanProc
    property int revision: 0
    property string scanPath: ""
    property string query: ""
    property string collected: ""
    stdout: SplitParser { onRead: function(data) { fileScanProc.collected += data + "\n" } }
    onExited: function(exitCode) {
      if (fileScanProc.revision !== root.fileScanSerial || !root.fileBrowserActive) return
      if (fileScanProc.scanPath !== root.fileBrowserPath || fileScanProc.query !== root.filterText.trim()) return
      var entries = []
      if (exitCode === 0) {
        var lines = fileScanProc.collected.split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].trim()) continue
          try { entries.push(JSON.parse(lines[i])) } catch (e) {}
        }
      }
      root.fileEntries = entries
      root.rebuildFileDisplay()
    }
  }

  Timer {
    id: extensionQueryTimer
    interval: 140
    repeat: false
    onTriggered: {
      var query = root.filterText.trim()
      var extension = MenuModel.queryExtension(root.extensions, query)
      if (!extension) return
      root.resultExtension = extension
      extensionQueryProc.query = query
      extensionQueryProc.extensionId = extension.id
      extensionQueryProc.revision = root.extensionQuerySerial
      extensionQueryProc.collected = ""
      extensionQueryProc.outputOverflow = false
      extensionQueryProc.command = root.commandArguments(extension.command, { query: query, extensionDir: extension.sourceDir })
      extensionQueryProc.running = true
      extensionQueryTimeout.restart()
    }
  }

  Timer {
    id: extensionQueryTimeout
    interval: 5000
    repeat: false
    onTriggered: if (extensionQueryProc.running) extensionQueryProc.running = false
  }

  Process {
    id: extensionQueryProc
    property string query: ""
    property string extensionId: ""
    property string collected: ""
    property bool outputOverflow: false
    property int revision: 0
    stdout: SplitParser {
      onRead: function(data) { root.collectBounded(extensionQueryProc, data) }
    }
    onExited: function(exitCode) {
      extensionQueryTimeout.stop()
      if (extensionQueryProc.revision !== root.extensionQuerySerial || extensionQueryProc.query !== root.filterText.trim()) return
      if (!root.resultExtension || extensionQueryProc.extensionId !== root.resultExtension.id) return
      root.extensionQuery = extensionQueryProc.query
      root.extensionResult = exitCode === 0 && !extensionQueryProc.outputOverflow ? extensionQueryProc.collected.trim() : ""
      root.rebuildDisplay()
      if (root.extensionResult && root.resultExtension.capability === "currency") currencyRates.refreshIfStale()
    }
  }

  Process {
    id: extensionProc
    property string collected: ""
    property bool outputOverflow: false
    stdout: SplitParser {
      onRead: function(data) { root.collectBounded(extensionProc, data) }
    }
    onExited: function(exitCode) {
      var catalog = exitCode === 0 && !extensionProc.outputOverflow
        ? MenuModel.parseExtensionCatalog(extensionProc.collected)
        : { extensions: [], diagnostics: [extensionProc.outputOverflow ? "Extension catalog exceeded the output limit" : "Extension loader exited with code " + exitCode] }
      root.extensions = catalog.extensions
      root.extensionDiagnostics = catalog.diagnostics
      for (var i = 0; i < catalog.diagnostics.length; i++) console.warn("Omalaunch: " + catalog.diagnostics[i])
      if (root.opened && !root.dmenuActive) {
        root.scheduleExtensionQuery()
        root.rebuildDisplay()
      }
      if (root.extensionsReloadPending) root.loadExtensions()
    }
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property bool outputOverflow: false
    property int revision: 0
    stdout: SplitParser {
      onRead: function(data) { root.collectBounded(providerProc, data) }
    }
    onExited: {
      if (!providerProc.outputOverflow && providerProc.revision === root.providerRevision) {
        root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
        if (root.filterText.trim()) root.loadProvidersForSearch()
      }
      root.startNextProvider()
    }
  }

  Process {
    id: resultProc
    property int requestId: 0
    onExited: root.startResultWrite()
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }

  Connections {
    target: favorites
    function onChanged() {
      if (!root.opened || root.dmenuActive) return
      var selectedId = root.pendingStarSelectionId
      root.pendingStarSelectionId = ""
      root.rebuildDisplay()
      if (!selectedId) return
      for (var i = 0; i < displayModel.count; i++) {
        if (displayModel.get(i).itemId !== selectedId) continue
        root.selectedIndex = i
        root.cursorActive = true
        root.revealCursor()
        break
      }
    }
  }

  // The JSONC sources are watched so live edits to the default file (or the
  // user extension at ~/.config/omarchy/extensions/omarchy-menu.jsonc) take
  // effect without restarting the shell.
  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onLoadFailed: { root.userMenuItems = []; root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  // ---------------------------------------------------------------- guards
  //
  // `when:` (visibility) and `checked:` (✓ marker) are bash expressions the
  // shell wasn't allowed to evaluate before the perf rewrite. Now the shell
  // batches them into one bash subprocess per (re)load so the open path
  // never has to wait on them.

  property var whenResults: ({})       // id → true|false (allow visibility)
  property var checkedResults: ({})    // id → true|false (show ✓)
  property bool guardsPending: false

  function evaluateGuards() {
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      root.guardsPending = true
      return
    }
    root.guardsPending = false

    var script = MenuModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { guardProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      // A batch that was killed rather than finished has only told us about
      // the rows it reached, and a row whose `when:` went unanswered shows.
      // Keep the last complete set rather than let a half-read one through.
      // A signal leaves the exit code at 0, so the status is what tells us.
      if (exitCode !== 0 || exitStatus !== 0) {
        if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") nextWhen[id] = value
        else if (tag === "c") nextChecked[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      if (root.opened) root.rebuildDisplay()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
      if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
    }
  }
  PanelWindow {
    id: panel
    visible: root.opened && root.rowsLoaded
    anchors { top: true; bottom: true; left: true; right: true }
    // Map the layer at output size on first show. If the window sizes to the
    // compact card, later growth is clipped and the list only scrolls in place.
    implicitWidth: screen && screen.width > 0 ? screen.width : 1920
    implicitHeight: screen && screen.height > 0 ? screen.height : 1080
    color: "transparent"
    WlrLayershell.namespace: "omarchy-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // Park the compact card in the upper portion of the layer so there is
    // room to grow down. Use panel.height (layer Y), not overlayHeight:
    // on scaled outputs overlayHeight can follow screen.height in a
    // different unit and drop a small card back near visual center.
    // First search or submenu freeze that top edge so later resizes don't jump.
    property int cardTop: -1
    readonly property int centeredTop: {
      var h = panel.height > 0 ? panel.height : root.overlayHeight
      return Math.max(Style.gapsOut, Math.round(h * 0.15))
    }
    readonly property int effectiveCardTop: cardTop >= 0 ? cardTop : centeredTop
    function freezeCardTop() {
      if (visible && cardTop < 0) {
        cardTop = effectiveCardTop
        root.layoutSerial += 1
      }
    }
    onVisibleChanged: if (!visible) cardTop = -1

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      y: panel.effectiveCardTop
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.deleteConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.deleteConfirmOpen) {
            if (deleteConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (root.fileBrowserActive && !root.actionPanelActive && event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) {
            root.openActionPanel()
            event.accepted = true
          } else if (root.fileBrowserActive && !root.actionPanelActive && event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
            root.copySelectedFilePath()
            event.accepted = true
          } else if (!root.dmenuActive && event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
            root.toggleSelectedStar()
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            root.requestDeleteSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.actionPanelActive) root.closeActionPanel()
            else if (root.filterText) root.setFilter("")
            else if (root.fileBrowserActive) root.leaveFileBrowser()
            else root.cancel()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
            if (root.actionPanelActive) root.closeActionPanel()
            else if (root.fileBrowserActive) {
              if (root.fileBrowserPath === "/") root.leaveFileBrowser()
              else {
                root.fileBrowserPath = root.parentPath(root.fileBrowserPath)
                root.fileEntries = []
                root.selectedIndex = 0
                root.scheduleFileScan()
              }
            } else root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            if (root.dmenuActive) {
              if (root.mode === "input") root.applyDmenuSelection(root.filterText)
              else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
            } else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: deleteConfirm

          anchors.fill: parent
          opened: root.deleteConfirmOpen
          z: 10
          message: "Do you want to uninstall " + ((root.deleteTarget && root.deleteTarget.label) || "") + "?"
          confirmText: "Uninstall"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelDelete()
          onConfirmed: root.confirmDelete()
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            anchors.left: parent.left
            anchors.right: starHint.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: root.actionPanelActive
              ? ("Actions for " + ((root.actionPanelFile && root.actionPanelFile.name) || "file"))
              : root.fileBrowserActive
                ? (root.fileBrowserPath + (root.filterText ? "  ›  " + root.filterText : ""))
              : (root.filterText || (root.dmenuActive ? (root.dmenuPrompt + "…") : ((root.item(root.activeMenu) ? (root.item(root.activeMenu).title || root.item(root.activeMenu).label) : "Go") + "…")))
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Text {
            id: starHint
            visible: !root.actionPanelActive && !root.dmenuActive && displayModel.count > 0 && root.cursorActive && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count && (root.fileBrowserActive || (displayModel.get(root.selectedIndex).itemId !== "omarchy" && displayModel.get(root.selectedIndex).itemId !== "extension.result"))
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.fileBrowserActive ? "Ctrl+K  Actions" : (root.cursorActive && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count && displayModel.get(root.selectedIndex).starred ? "Ctrl+S  Unstar" : "Ctrl+S  Star")
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

        }

        Item {
          width: parent.width
          height: root.visibleRowsHeight

          ListView {
            id: resultList
            anchors.fill: parent
            anchors.rightMargin: root.imagePreviewActive ? root.previewPaneWidth + root.contentSpacing : 0
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            section.property: "section"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
              required property string section

              width: ListView.view.width
              height: section === "drilldown" ? root.dividerHeight : 0
              visible: section === "drilldown"

              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.spacing.hairline
                color: Util.alpha(root.foreground, 0.2)
              }
            }

            delegate: BorderSurface {
              id: row
              required property int index
              required property string itemId
              required property string kind
              required property string icon
              required property string iconFont
              required property string appIcon
              required property string appId
              required property string label
              required property string target
              required property string detail
              required property string path
              required property string action
              required property int childCount
              required property bool starred

              readonly property bool hasCursor: root.cursorActive && row.index === root.selectedIndex
              readonly property bool isApp: row.kind === "app"
              readonly property bool isImageFile: row.itemId.indexOf("file.item.") === 0 && MenuModel.isImagePath(row.action)
              readonly property bool hasIcon: row.icon.length > 0 || row.isApp || row.isImageFile

              width: ListView.view.width
              height: root.rowHeightForDetail(row.detail)
              radius: root.cornerRadius
              color: row.hasCursor ? root.selectedBackground : "transparent"
              borderSpec: row.hasCursor ? root.selectedBorderSpec : Border.none()

              Rectangle {
                visible: false
                width: Style.space(4)
                height: parent.height - Style.space(18)
                radius: Math.min(root.cornerRadius, Style.space(4))
                color: root.selectedBackground
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: iconText
                visible: row.hasIcon && !row.isApp && !row.isImageFile
                text: row.icon
                color: row.hasCursor ? root.selectedText : root.foreground
                font.family: row.iconFont.length > 0 ? row.iconFont : root.fontFamily
                font.pixelSize: Style.font.iconLarge
                width: Style.space(36)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              Rectangle {
                id: imagePreview
                visible: row.isImageFile
                width: Style.space(36)
                height: Style.space(36)
                radius: Math.min(root.cornerRadius, Style.space(5))
                color: Util.alpha(root.foreground, 0.08)
                clip: true
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2

                Image {
                  anchors.fill: parent
                  source: row.isImageFile ? MenuModel.localFileUrl(row.action) : ""
                  fillMode: Image.PreserveAspectCrop
                  sourceSize.width: width * Screen.devicePixelRatio
                  sourceSize.height: height * Screen.devicePixelRatio
                  asynchronous: true
                  cache: true
                }
              }

              Image {
                id: appIconImage
                visible: row.isApp
                width: Style.font.iconLarge
                height: Style.font.iconLarge
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels — a logical-size decode leaves
                // PNG icons upscaled and blurry on HiDPI displays.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: row.isApp && root.appLibrary ? root.appLibrary.iconSource(row.appIcon) : ""
                asynchronous: true
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8) + (Style.space(36) - width) / 2
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              Column {
                id: contentColumn
                anchors.left: row.isImageFile ? imagePreview.right : (row.hasIcon ? iconText.right : parent.left)
                anchors.leftMargin: row.hasIcon ? Style.space(6) : root.rowReservedBorderLeft + Style.space(18)
                anchors.right: trail.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  id: labelText
                  width: parent.width
                  text: row.label
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: row.detail
                  visible: (root.filterText || row.kind === "dmenu") && row.detail.length > 0
                  color: root.foreground
                  opacity: 0.52
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              Row {
                id: trail
                width: Style.space(14)
                anchors.right: parent.right
                anchors.rightMargin: root.rowReservedBorderRight + Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
                spacing: 0

                Text {
                  visible: false
                  text: row.childCount
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: row.starred ? "★" : (row.kind === "menu" || row.kind === "link" ? "›" : "")
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.starred ? 0.7 : (row.kind === "menu" || row.kind === "link" ? 0.36 : 0)
                  font.family: root.fontFamily
                  font.pixelSize: row.starred ? Style.font.bodySmall : Style.font.heading
                  font.weight: Font.Normal
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectFromPointer(row.index, row, {
                  x: mouseArea.mouseX,
                  y: mouseArea.mouseY
                })
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index, true)
                }
              }
            }
          }

          BorderSurface {
            id: previewPane
            visible: root.imagePreviewActive
            width: root.previewPaneWidth
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            radius: root.cornerRadius
            color: Util.alpha(root.foreground, 0.035)
            borderSpec: Border.none()
            padding: Style.space(12)

            Image {
              id: selectedImagePreview
              anchors.fill: parent
              anchors.leftMargin: previewPane.contentLeftInset
              anchors.rightMargin: previewPane.contentRightInset
              anchors.topMargin: previewPane.contentTopInset
              anchors.bottomMargin: previewPane.contentBottomInset + previewCaption.height + Style.space(8)
              source: root.imagePreviewActive ? MenuModel.localFileUrl(root.selectedFilePath) : ""
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              cache: true
            }

            Text {
              id: previewCaption
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.leftMargin: previewPane.contentLeftInset
              anchors.rightMargin: previewPane.contentRightInset
              anchors.bottomMargin: previewPane.contentBottomInset
              text: root.selectedFileRow ? root.selectedFileRow.label : ""
              color: root.foreground
              opacity: 0.72
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideMiddle
            }
          }

          // Scroll scrims. The clipped row already marks the fold at rest;
          // these keep both edges honest once the list has been scrolled,
          // when content hides above the card top as well as below. Strength
          // tracks the distance still hidden past each edge rather than
          // animating on a clock, so a programmatic jump — wrapping from the
          // last row back to the first — lands with the fade already applied.
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: root.imagePreviewActive ? root.previewPaneWidth + root.contentSpacing : 0
            anchors.top: parent.top
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.contentY - resultList.originY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: root.background }
              GradientStop { position: 1; color: Util.alpha(root.background, 0) }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: root.imagePreviewActive ? root.previewPaneWidth + root.contentSpacing : 0
            anchors.bottom: parent.bottom
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.originY + resultList.contentHeight - resultList.height - resultList.contentY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: Util.alpha(root.background, 0) }
              GradientStop { position: 1; color: root.background }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0 && root.mode !== "input" && (root.filterText || root.activeMenu !== "root") && !root.isPotentialExtensionQuery(root.filterText)

            Text {
              text: "󰈉"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }

            Text {
              text: root.filterText ? "No matches for “" + root.filterText + "”" : "Nothing here yet"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }
          }
        }

        Item {
          width: parent.width
          height: 0
        }
      }
    }
  }
}
