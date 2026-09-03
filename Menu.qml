import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel
import "MenuMarkdown.js" as MenuMarkdown
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
  property bool routePendingForMenuSources: false

  function open(payloadJson) {
    // Parse first so resetting the old surface cannot discard the incoming
    // request. Completion of a replaced dmenu is queued before its protocol
    // fields are cleared and before the new surface is installed.
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    root.resetForOpen()
    root.loadExtensions(false)

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
    root.requestDefaultMenuReload()
    root.requestUserMenuReload()
    root.loadExtensions(true)
    return "ok"
  }

  function ping() { return "ok" }

  property string fontFamily: Style.font.menuFamily

  function styleFontSize(fontClass) {
    switch (fontClass) {
    case "caption": return Style.font.caption
    case "bodySmall": return Style.font.bodySmall
    case "subtitle": return Style.font.subtitle
    case "title": return Style.font.title
    case "heading": return Style.font.heading
    case "display": return Style.font.display
    case "displayLarge": return Style.font.displayLarge
    default: return Style.font.body
    }
  }

  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  property var defaultMenuItems: []
  property var userMenuItems: []
  property bool defaultMenuSettled: false
  property bool userMenuSettled: false
  // FileView does not queue reload() while an asynchronous read is active.
  // Track each read and collapse intervening changes into one trailing reload.
  property bool defaultMenuLoading: true
  property bool userMenuLoading: true
  property bool defaultMenuReloadPending: false
  property bool userMenuReloadPending: false
  property var extensions: []
  property var extensionDiagnostics: []
  property var unavailableResultExtension: null
  property bool extensionsReloadPending: false
  property double extensionsLoadedAt: 0
  readonly property int extensionRefreshTtlMs: 10 * 1000
  property bool opened: false
  property string mode: "menu"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  readonly property bool workflowInputActive: workflowActive && workflowNode && workflowNode.kind === "input"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property var dmenuRows: []
  readonly property int maxDisplayedResults: 100
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
  property var itemMetadata: ({})
  property var searchExcludedRoots: ["setup.default"]
  property var navStack: []
  property var providersLoaded: ({})
  property var providerQueue: []
  property int providerRevision: 0
  property string extensionQuery: ""
  property string extensionResult: ""
  property var resultExtension: null
  // A root shortcut can focus one extension's input without creating a second
  // favorites system or changing direct typed extension invocation.
  property var focusedExtension: null
  property int extensionQuerySerial: 0
  property int extensionQueryGeneration: 0
  property var pendingExtensionQuery: null
  readonly property int extensionQueryTimeoutMs: 5000
  readonly property int extensionQueryTerminationGraceMs: 500
  property bool fileBrowserActive: false
  property bool directoryPickerActive: false
  property var fileBrowserExtension: null
  property string fileBrowserPath: ""
  property var fileEntries: []
  property bool workflowActive: false
  readonly property int workflowMaxDepth: 8
  property var workflowExtension: null
  property var workflowNode: null
  property var workflowContext: ({})
  property var workflowStack: []
  property bool dynamicMenuLoading: false
  property bool submenuLoading: false
  property int submenuGeneration: 0
  readonly property int submenuTimeoutMs: 5000
  readonly property int submenuTerminationGraceMs: 500
  readonly property int submenuOutputBytes: 256 * 1024
  property bool documentLoading: false
  property string documentError: ""
  property int documentGeneration: 0
  readonly property int documentTimeoutMs: 5000
  readonly property int documentTerminationGraceMs: 500
  readonly property int documentOutputBytes: 256 * 1024
  readonly property bool documentActive: root.workflowActive && root.workflowNode
    && root.workflowNode.kind === "document"
  readonly property var activeDocument: root.documentActive ? root.workflowNode.document : null
  property var workflowConfirmNode: null
  property bool workflowConfirmOpen: false
  property int dynamicMenuGeneration: 0
  readonly property int dynamicMenuTimeoutMs: 5000
  readonly property int dynamicMenuTerminationGraceMs: 500
  readonly property int dynamicMenuOutputBytes: 256 * 1024
  property var dynamicMenuSearchSnapshot: []
  property var dynamicMenuSearchQueue: []
  property var dynamicMenuSearchCandidate: []
  property int dynamicMenuSearchGeneration: 0
  property int dynamicMenuSearchOutputBytes: 0
  readonly property int dynamicMenuSearchMaxProviders: 16
  readonly property int dynamicMenuSearchMaxRows: 1000
  readonly property int dynamicMenuSearchMaxOutputBytes: 1024 * 1024
  readonly property int dynamicMenuSearchTotalTimeoutMs: 10 * 1000
  property int workflowGeneration: 0
  readonly property int workflowActionTimeoutMs: 30 * 1000
  readonly property int workflowTerminationGraceMs: 1000
  property int backgroundActionGeneration: 0
  readonly property int backgroundActionTimeoutMs: 30 * 1000
  readonly property int backgroundDiagnosticTextLimit: 256
  property int fileScanSerial: 0
  readonly property string fileIndexHelper: root.pluginPath + "/extensions/files/file-index.py"
  readonly property string extensionLoaderHelper: root.pluginPath + "/libexec/load-extensions.py"
  readonly property string configHelper: root.pluginPath + "/libexec/omalaunch-config"
  readonly property string fileIndexInstanceId: Date.now() + "-" + Math.floor(Math.random() * 1000000000)
  readonly property string fileIndexPathPrefix: Quickshell.env("XDG_RUNTIME_DIR")
    ? Quickshell.env("XDG_RUNTIME_DIR") + "/omalaunch-file-index-" + root.fileIndexInstanceId
    : "/tmp/omalaunch-file-index-" + Quickshell.env("USER") + "-" + root.fileIndexInstanceId
  property string fileIndexPath: ""
  property string fileIndexRoot: ""
  property bool fileIndexReady: false
  property bool fileBrowserShowHidden: false
  property int fileIndexSerial: 0
  property double fileIndexBuiltAt: 0
  readonly property int fileIndexTtlMs: 30 * 1000
  property string fileCopyFeedbackPath: ""
  property string fileCopyFeedback: ""
  property bool actionPanelActive: false
  property string settingsFeedback: ""
  property var actionPanelFile: null
  readonly property var selectedFileRow: root.fileBrowserActive && !root.actionPanelActive && root.cursorActive
    && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count
    ? displayModel.get(root.selectedIndex) : null
  readonly property string selectedFilePath: root.selectedFileRow ? String(root.selectedFileRow.action || "") : ""
  readonly property bool imagePreviewActive: MenuModel.isImagePath(root.selectedFilePath)
  readonly property var selectedWorkflowNode: root.workflowActive && !root.fileBrowserActive
    && root.workflowNode && root.workflowNode.kind === "menu" && root.cursorActive
    && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count
    ? root.workflowNode.items[Number(displayModel.get(root.selectedIndex).action)] : null
  readonly property bool selectedWorkflowHasActions: root.selectedWorkflowNode
    && root.selectedWorkflowNode.actions && root.selectedWorkflowNode.actions.length > 0
  readonly property var selectedWorkflowStarAction: root.workflowStarAction(root.selectedWorkflowNode)
  readonly property var selectedDynamicSearchEntry: !root.workflowActive && root.cursorActive
    && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count
    ? root.dynamicMenuSearchEntry(displayModel.get(root.selectedIndex).itemId) : null
  readonly property var selectedDynamicStarAction: root.selectedDynamicSearchEntry
    ? root.workflowStarAction(root.selectedDynamicSearchEntry.node) : null
  readonly property int previewPaneWidth: Math.round((root.cardWidth
    - card.contentLeftInset - card.contentRightInset - root.contentSpacing) / 2)

  // Shared application engine (entries, hidden filters, icons, launch,
  // removal), owned by the shell and also used by the standalone launcher.
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property int appIconRefreshTtlMs: 30 * 1000
  property double appIconIndexUpdatedAt: 0
  property bool appIconRefreshPending: false
  onAppLibraryChanged: {
    root.appIconIndexUpdatedAt = 0
    root.appIconRefreshPending = false
    // A provider request can race shell injection. Reconcile loaded app rows
    // after attachment or detachment; mergeAppRows() also clears stale rows
    // when no library is attached.
    if (root.providersLoaded["apps"]) {
      var revision = root.providerRevision
      Qt.callLater(function() {
        if (revision === root.providerRevision && root.providersLoaded["apps"])
          root.mergeAppRows()
      })
    }
  }
  property bool deleteConfirmOpen: false
  property bool dependencyConfirmOpen: false
  property string pendingStarSelectionId: ""
  property var deleteTarget: null
  property var dependencyTarget: null
  onOpenedChanged: if (!opened) {
    root.invalidateWorkflowAction("launcher closed")
    root.invalidateBackgroundAction("launcher closed")
    root.invalidateSubmenu("launcher closed")
    root.invalidateDocument("launcher closed")
    root.invalidateDynamicMenu()
    root.invalidateExtensionQuery("launcher closed")
    deleteConfirmOpen = false
    deleteTarget = null
    dependencyConfirmOpen = false
    dependencyTarget = null
  }
  // Bound to the central [menu] section in shell.toml via Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  LauncherFavorites {
    id: favorites
    helperPath: root.pluginPath + "/libexec/provider-config"
    extensions: root.extensions
  }
  LauncherUsage { id: usage }
  CurrencyExtension.CurrencyRates { id: currencyRates }

  Connections {
    target: currencyRates
    function onRefreshed() {
      if (!root.resultExtension || root.resultExtension.capability !== "currency") return
      root.scheduleExtensionQuery()
    }
  }

  property color background: Color.menu.background
  // Menu theme surfaces can include alpha. Confirmation cards must be opaque
  // because they are rendered over the menu card and its rows.
  readonly property color dialogBackground: Qt.rgba(background.r, background.g, background.b, 1)
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
  property int headerHeight: Math.max(Style.space(28), Math.round(Style.space(34) * menuItemScale))
  property int actionBarHeight: Math.max(Style.space(26), Math.round(Style.space(36) * menuItemScale))
  property int actionBarBottomPadding: Style.space(6)
  property int contentSpacing: Style.spacing.md
  property string menuItemFontClass: "title"
  property int configuredMenuItemFontSize: 0
  readonly property int menuItemFontSize: configuredMenuItemFontSize > 0
    ? configuredMenuItemFontSize : styleFontSize(menuItemFontClass)
  readonly property real menuItemScale: menuItemFontSize / Style.font.body
  readonly property int menuSecondaryFontSize: Math.max(1, Math.round(Style.font.bodySmall * menuItemScale))
  readonly property int menuCaptionFontSize: Math.max(1, Math.round(Style.font.caption * menuItemScale))
  readonly property int menuItemIconSize: Math.max(Style.space(10), Math.min(Style.space(32),
    Math.round(menuItemFontSize * 1.25)))
  property int baseRowHeight: Math.max(Style.space(28), Math.round(Style.space(44) * menuItemScale))
  property int detailRowHeight: Math.max(Style.space(36), Math.round(Style.space(52) * menuItemScale))
  // How much of the first hidden row stays visible at the fold — enough to
  // read as a cut-off row rather than a bottom border.
  property int rowPeek: Math.round(baseRowHeight * 0.55)
  property int rowSpacing: Math.max(Style.space(1), Math.round(Style.spacing.xs * menuItemScale))
  property int dividerHeight: Style.space(17)
  property bool searchDivider: false
  property int layoutSerial: 0
  property int cardWidth: Math.min(root.dmenuActive
    ? Style.space(root.dmenuWidth)
    : Style.space(root.imagePreviewActive ? 900 : (root.documentActive ? 760 : 600)), panel.width - Style.gapsOut * 2)
  readonly property bool emptyRoot: !root.dmenuActive && !root.workflowActive
    && root.activeMenu === "root" && !root.filterText && displayModel.count === 0
  property int visibleRowsHeight: root.emptyRoot || root.workflowInputActive ? 0
    : (root.documentActive ? Math.min(Style.space(520), Math.max(Style.space(260), panel.height - panel.pinnedTop
      - Style.gapsOut - root.contentMargin - root.actionBarBottomPadding - root.headerHeight
      - root.actionBarHeight - root.contentSpacing * 2))
    : (root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText)
      : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)))
  readonly property bool workflowFilterMenuActive: root.workflowActive && root.workflowNode && root.workflowNode.kind === "menu"
  property int workflowHintHeight: (root.workflowInputActive || root.workflowFilterMenuActive)
    ? Math.max(Style.space(12), Math.round(Style.space(18) * menuItemScale)) : 0
  property int cardHeight: Math.min(contentMargin + actionBarBottomPadding + headerHeight + actionBarHeight + contentSpacing
    + (visibleRowsHeight > 0 ? contentSpacing + visibleRowsHeight : 0)
    + (workflowHintHeight > 0 ? contentSpacing + workflowHintHeight : 0), panel.height - Style.gapsOut * 2)

  readonly property var actionBarHints: MenuModel.actionBarHints({
    dmenuActive: root.dmenuActive,
    dmenuInput: root.dmenuActive && root.mode === "input",
    workflowActive: root.workflowActive,
    workflowInputActive: root.workflowInputActive,
    fileBrowserActive: root.fileBrowserActive,
    directoryPickerActive: root.directoryPickerActive,
    actionPanelActive: root.actionPanelActive,
    canContextActions: root.selectedWorkflowHasActions
      || (root.documentActive && root.activeDocument && root.activeDocument.actions.length > 0)
      || (root.selectedDynamicSearchEntry && root.selectedDynamicSearchEntry.node.actions.length > 0),
    focusedExtension: !!root.focusedExtension,
    hasSelection: displayModel.count > 0 && root.cursorActive,
    canStar: (!root.dmenuActive && !root.workflowActive && !root.actionPanelActive) || !!root.selectedWorkflowStarAction || !!root.selectedDynamicStarAction
      && displayModel.count > 0 && root.cursorActive && root.selectedIndex >= 0
      && root.selectedIndex < displayModel.count
      && (root.fileBrowserActive || (displayModel.get(root.selectedIndex).itemId !== "omarchy"
        && displayModel.get(root.selectedIndex).itemId !== "extensions"
        && displayModel.get(root.selectedIndex).itemId !== "extension.result"
        && displayModel.get(root.selectedIndex).itemId !== "extension.result.pending")),
    starred: displayModel.count > 0 && root.cursorActive && root.selectedIndex >= 0
      && root.selectedIndex < displayModel.count && displayModel.get(root.selectedIndex).starred
  })
  readonly property real actionBarFontScale: menuItemFontSize / Style.font.title
  readonly property var displayedActionBarHints: root.cardWidth
    < Math.round(Style.space(560) * Math.max(1, actionBarFontScale))
    ? MenuModel.compactActionBarHints(root.actionBarHints) : root.actionBarHints

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

  function refreshAppIconsIfStale() {
    if (!root.appLibrary || root.appIconRefreshPending) return
    if (root.appIconIndexUpdatedAt > 0
        && Date.now() - root.appIconIndexUpdatedAt < root.appIconRefreshTtlMs) return
    root.appIconRefreshPending = true
    root.appLibrary.refreshIcons()
  }

  function badgeToneColor(tone) {
    if (tone === "success") return "#3fb950"
    if (tone === "danger") return "#f85149"
    if (tone === "warning") return "#d29922"
    if (tone === "info") return "#58a6ff"
    return root.foreground
  }

  // Menu rows only surface their detail while a search is narrowing them;
  // dmenu rows carry caller-supplied subtext that must always be visible.
  function rowHeightForDetail(detail) {
    return (root.filterText || root.dmenuActive) && detail ? root.detailRowHeight : root.baseRowHeight
  }

  // Height the card can devote to rows below its pinned top edge.
  function availableRowsHeight() {
    var available = panel.height - panel.pinnedTop - Style.gapsOut - root.contentMargin - root.actionBarBottomPadding
      - root.headerHeight - root.actionBarHeight - root.contentSpacing * 2
    // A card that swallows the whole screen reads as a page, not a menu.
    return Math.min(available, Math.round(panel.height * 0.5))
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
    if (displayModel.count === 0) return root.baseRowHeight

    var totals = []
    var total = 0
    var previousSection = ""

    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (i > 0) total += root.rowSpacing
      if (row.section === "drilldown" && previousSection !== "drilldown") total += root.dividerHeight
      total += root.rowHeightForDetail(row.detail)
      previousSection = row.section
      totals.push(total)
    }

    return foldedListHeight(totals, availableRowsHeight())
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

  function loadExtensions(force) {
    var forced = force === true
    if (extensionProc.running) {
      // An ordinary open can reuse the catalog already being loaded. Only an
      // explicit refresh needs a follow-up run after the current one exits.
      if (forced) root.extensionsReloadPending = true
      return
    }
    if (!forced && root.extensionsLoadedAt > 0
        && Date.now() - root.extensionsLoadedAt < root.extensionRefreshTtlMs) return
    root.extensionsReloadPending = false
    extensionProc.collected = ""
    extensionProc.outputOverflow = false
    // The helper invokes provider argument arrays directly. No provider value
    // is interpolated into a shell command.
    extensionProc.command = [root.extensionLoaderHelper, root.pluginPath, root.omarchyPath]
    extensionProc.running = true
  }

  function isPotentialExtensionQuery(value) {
    var query = String(value || "")
    return /^\s*[+-]?\s*(?:\d|\.\d|\([\s(+\-]*(?:\d|\.\d))/.test(query)
      || MenuModel.queryExtension(root.extensions, query) !== null
      || MenuModel.unavailableQueryExtension(root.extensions, query) !== null
  }

  function stopExtensionQuery(reason) {
    extensionQueryTimeout.stop()
    if (!extensionQueryProc.running || extensionQueryProc.stopping) return
    // Keep every field describing this child immutable until onExited. Setting
    // running false is Quickshell's SIGTERM path; only the matching generation
    // may escalate the same direct child after the grace period.
    extensionQueryProc.stopping = true
    extensionQueryProc.stopGeneration = extensionQueryProc.generation
    extensionQueryKillTimer.generation = extensionQueryProc.stopGeneration
    extensionQueryProc.running = false
    extensionQueryKillTimer.restart()
  }

  function invalidateExtensionQuery(reason) {
    root.extensionQuerySerial += 1
    extensionQueryTimer.stop()
    root.pendingExtensionQuery = null
    root.stopExtensionQuery(reason)
  }

  function dispatchPendingExtensionQuery() {
    if (extensionQueryProc.running || extensionQueryProc.stopping || !root.pendingExtensionQuery) return
    var request = root.pendingExtensionQuery
    root.pendingExtensionQuery = null
    if (!root.opened || request.revision !== root.extensionQuerySerial
        || request.query !== root.effectiveExtensionQuery()
        || !root.resultExtension || request.extensionId !== root.resultExtension.id) return

    root.extensionQueryGeneration += 1
    extensionQueryProc.generation = root.extensionQueryGeneration
    extensionQueryProc.revision = request.revision
    extensionQueryProc.query = request.query
    extensionQueryProc.extensionId = request.extensionId
    extensionQueryProc.collected = ""
    extensionQueryProc.outputOverflow = false
    extensionQueryProc.command = request.command
    extensionQueryProc.running = true
    extensionQueryTimeout.generation = extensionQueryProc.generation
    extensionQueryTimeout.restart()
  }

  function queueExtensionQuery(extension, query, revision) {
    root.pendingExtensionQuery = {
      extensionId: extension.id,
      query: query,
      revision: revision,
      command: root.commandArguments(extension.command, { query: query, extensionDir: extension.sourceDir })
    }
    if (extensionQueryProc.running && !extensionQueryProc.stopping)
      root.stopExtensionQuery("newer query queued")
    else if (!extensionQueryProc.stopping)
      root.dispatchPendingExtensionQuery()
  }

  function collectExtensionQuery(data) {
    if (extensionQueryProc.outputOverflow || extensionQueryProc.stopping) return
    var next = extensionQueryProc.collected + data + "\n"
    if (next.length > root.maxProcessOutputBytes) {
      extensionQueryProc.outputOverflow = true
      extensionQueryProc.collected = ""
      root.stopExtensionQuery("query output exceeded limit")
      return
    }
    extensionQueryProc.collected = next
  }

  function scheduleExtensionQuery() {
    root.invalidateExtensionQuery("query context changed")
    root.extensionQuery = ""
    root.extensionResult = ""
    root.resultExtension = null
    root.unavailableResultExtension = null
    if (root.dmenuActive || !root.opened) return
    if (root.focusedExtension && root.focusedExtension.mode === "prefix") {
      root.rebuildDisplay()
      return
    }

    var query = root.effectiveExtensionQuery()
    var queryCatalog = root.focusedExtension ? [root.focusedExtension] : root.extensions
    root.resultExtension = MenuModel.queryExtension(queryCatalog, query)
    root.unavailableResultExtension = MenuModel.unavailableQueryExtension(queryCatalog, query)
    if (root.resultExtension) extensionQueryTimer.restart()
    // Available queries rebuild when their process exits. Unavailable queries
    // start no process, so surface their actionable row immediately.
    else if (root.unavailableResultExtension) root.rebuildDisplay()
  }

  function extensionById(id) {
    for (var i = 0; i < root.extensions.length; i++)
      if (root.extensions[i].id === id) return root.extensions[i]
    return null
  }

  function extensionByCapability(capability) {
    for (var i = 0; i < root.extensions.length; i++)
      if (root.extensions[i].capability === capability) return root.extensions[i]
    return null
  }

  function extensionForRootId(itemId) {
    return root.extensionByCapability(MenuModel.extensionRootCapability(itemId))
  }

  function focusedExtensionPlaceholder() {
    if (!root.focusedExtension) return ""
    if (root.focusedExtension.capability === "calculator") return "Enter a calculation…"
    if (root.focusedExtension.capability === "currency") return "Enter a conversion…"
    if (root.focusedExtension.capability === "timezone") return "Enter a timezone query…"
    return "Start typing…"
  }

  function effectiveExtensionQuery() {
    return root.focusedExtension
      ? MenuModel.focusedExtensionQuery(root.focusedExtension, root.filterText)
      : root.filterText.trim()
  }

  function enterFocusedExtension(extension) {
    if (!extension || !extension.available) return
    root.focusedExtension = extension
    root.activeMenu = "extensions"
    root.navStack = ["root"]
    root.filterText = MenuModel.extensionRootInput(extension)
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
    root.scheduleExtensionQuery()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function leaveFocusedExtension() {
    root.invalidateExtensionQuery("left focused extension")
    root.focusedExtension = null
    root.extensionQuery = ""
    root.extensionResult = ""
    root.resultExtension = null
    root.unavailableResultExtension = null
    root.setActiveMenu("extensions", false)
  }

  function activateExtensionRoot(extension) {
    if (!extension) return
    if (!extension.available) {
      var setup = MenuModel.dependencySetup(extension)
      if (setup) {
        root.dependencyTarget = setup
        root.dependencyConfirmOpen = true
      }
      return
    }
    var activation = MenuModel.extensionRootActivation(extension)
    if (activation === "files") root.enterFileBrowser(extension)
    else if (activation === "workflow") root.enterWorkflow(extension)
    else if (activation === "menu") root.enterDynamicMenu(extension)
    else if (activation === "input") root.enterFocusedExtension(extension)
  }

  function workflowValues(extra) {
    return Object.assign({}, root.workflowContext || ({}), {
      extensionDir: root.workflowExtension ? root.workflowExtension.sourceDir : ""
    }, extra || ({}))
  }

  function workflowText(value, extra) {
    return MenuModel.workflowInterpolate(value, root.workflowValues(extra))
  }

  function openDocumentLink(url) {
    var target = String(url || "")
    if (!/^https?:\/\/[^\s<>]+$/i.test(target)) return
    Quickshell.execDetached(["xdg-open", target])
  }

  function copyDocumentCode(value) {
    Quickshell.execDetached(["wl-copy", "--", String(value || "")])
  }

  function workflowNodeContext(node, base) {
    var result = Object.assign({}, base || ({}))
    var values = node && node.context ? node.context : ({})
    for (var key in values) result[key] = MenuModel.workflowInterpolate(values[key], Object.assign({}, result, { extensionDir: root.workflowExtension ? root.workflowExtension.sourceDir : "" }))
    return result
  }

  function invalidateDynamicMenu() {
    if (dynamicMenuProc.stopping) return
    dynamicMenuTimeout.stop()
    root.dynamicMenuGeneration += 1
    if (dynamicMenuProc.running) {
      dynamicMenuProc.stopping = true
      dynamicMenuProc.stopGeneration = dynamicMenuProc.generation
      dynamicMenuKillTimer.generation = dynamicMenuProc.stopGeneration
      dynamicMenuProc.running = false
      dynamicMenuKillTimer.restart()
    }
    root.dynamicMenuLoading = false
  }

  function invalidateDynamicMenuSearch() {
    root.dynamicMenuSearchGeneration += 1
    dynamicMenuSearchProviderTimeout.stop()
    dynamicMenuSearchTotalTimeout.stop()
    root.dynamicMenuSearchQueue = []
    root.dynamicMenuSearchCandidate = []
    if (dynamicMenuSearchProc.running) {
      dynamicMenuSearchProc.stopping = true
      dynamicMenuSearchProc.stopGeneration = dynamicMenuSearchProc.generation
      dynamicMenuSearchKillTimer.generation = dynamicMenuSearchProc.stopGeneration
      dynamicMenuSearchProc.running = false
      dynamicMenuSearchKillTimer.restart()
    }
  }

  function preloadDynamicMenuSearch() {
    root.invalidateDynamicMenuSearch()
    var queue = []
    for (var i = 0; i < root.extensions.length; i++) {
      var extension = root.extensions[i]
      if (extension.mode === "menu" && extension.available && extension.globalSearch) queue.push(extension)
    }
    if (queue.length > root.dynamicMenuSearchMaxProviders) {
      console.warn("Omalaunch: global menu search preload exceeds the provider limit; retained the previous snapshot")
      return
    }
    if (queue.length === 0) {
      root.dynamicMenuSearchSnapshot = []
      root.rebuildDisplay()
      return
    }
    root.dynamicMenuSearchQueue = queue
    root.dynamicMenuSearchOutputBytes = 0
    dynamicMenuSearchTotalTimeout.generation = root.dynamicMenuSearchGeneration
    dynamicMenuSearchTotalTimeout.restart()
    root.startDynamicMenuSearchProvider()
  }

  function startDynamicMenuSearchProvider() {
    if (dynamicMenuSearchProc.running || dynamicMenuSearchProc.stopping || root.dynamicMenuSearchQueue.length === 0) return
    var extension = root.dynamicMenuSearchQueue[0]
    root.dynamicMenuSearchQueue = root.dynamicMenuSearchQueue.slice(1)
    dynamicMenuSearchProc.generation = root.dynamicMenuSearchGeneration
    dynamicMenuSearchProc.extension = extension
    dynamicMenuSearchProc.collected = ""
    dynamicMenuSearchProc.stderrBytes = 0
    dynamicMenuSearchProc.outputOverflow = false
    var searchCommand = extension.globalSearchCommand && extension.globalSearchCommand.length > 0
      ? extension.globalSearchCommand : extension.command
    dynamicMenuSearchProc.command = searchCommand.map(function(argument) {
      return MenuModel.workflowInterpolate(argument, { extensionDir: extension.sourceDir })
    })
    dynamicMenuSearchProc.running = true
    dynamicMenuSearchProviderTimeout.generation = root.dynamicMenuSearchGeneration
    dynamicMenuSearchProviderTimeout.restart()
  }

  function rejectDynamicMenuSearch(reason) {
    console.warn("Omalaunch: " + reason + "; retained the previous global menu search snapshot")
    root.invalidateDynamicMenuSearch()
  }

  function dynamicMenuSearchEntry(itemId) {
    for (var i = 0; i < root.dynamicMenuSearchSnapshot.length; i++)
      if (root.dynamicMenuSearchSnapshot[i].item.id === itemId) return root.dynamicMenuSearchSnapshot[i]
    return null
  }

  function enterDynamicMenu(extension, retainRows) {
    if (!extension || !extension.available || extension.mode !== "menu"
        || dynamicMenuProc.running || dynamicMenuProc.stopping) return
    var retainCurrentRows = retainRows === true && root.workflowActive && root.workflowNode
    root.invalidateExtensionQuery("entered dynamic menu")
    root.invalidateWorkflowAction("entered dynamic menu")
    root.invalidateDocument("entered dynamic menu")
    root.focusedExtension = null
    root.leaveFileBrowser(false)
    root.workflowActive = true
    root.workflowExtension = extension
    root.workflowStack = []
    root.workflowContext = ({ extensionDir: extension.sourceDir })
    if (!retainCurrentRows) {
      root.workflowNode = { id: "root", kind: "menu", label: extension.label, description: extension.description, items: [] }
      root.filterText = ""
      root.selectedIndex = 0
      root.cursorActive = false
    }
    root.dynamicMenuLoading = true
    root.dynamicMenuGeneration += 1
    dynamicMenuProc.generation = root.dynamicMenuGeneration
    dynamicMenuProc.extensionCapability = extension.capability
    dynamicMenuProc.selectionNodeId = retainCurrentRows && root.selectedWorkflowNode ? root.selectedWorkflowNode.id : ""
    dynamicMenuProc.collected = ""
    dynamicMenuProc.stderrBytes = 0
    dynamicMenuProc.outputOverflow = false
    dynamicMenuProc.command = extension.command.map(function(argument) {
      return MenuModel.workflowInterpolate(argument, { extensionDir: extension.sourceDir })
    })
    dynamicMenuProc.running = true
    dynamicMenuTimeout.restart()
    if (!retainCurrentRows) root.rebuildDisplay()
  }

  function invalidateSubmenu(reason) {
    if (submenuProc.stopping) return
    submenuTimeout.stop()
    root.submenuGeneration += 1
    if (submenuProc.running) {
      submenuProc.stopping = true
      submenuProc.stopGeneration = submenuProc.generation
      submenuKillTimer.generation = submenuProc.stopGeneration
      submenuProc.running = false
      submenuKillTimer.restart()
    }
    root.submenuLoading = false
  }

  function enterSubmenu(node) {
    if (!node || !node.submenuCommand || node.submenuCommand.length === 0
        || !root.workflowExtension || root.workflowStack.length >= root.workflowMaxDepth
        || submenuProc.running || submenuProc.stopping) return
    root.invalidateWorkflowAction("entered submenu")
    root.invalidateDocument("entered submenu")
    if (root.workflowNode)
      root.workflowStack = root.workflowStack.concat([{ node: root.workflowNode, context: root.workflowContext }])
    root.workflowContext = root.workflowNodeContext(node, root.workflowContext)
    root.workflowNode = { id: node.id + ".submenu", kind: "menu", label: node.label,
      description: "Loading…", items: [] }
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = false
    root.submenuLoading = true
    root.submenuGeneration += 1
    submenuProc.generation = root.submenuGeneration
    submenuProc.extensionCapability = root.workflowExtension.capability
    submenuProc.submenuNodeId = root.workflowNode.id
    submenuProc.collected = ""
    submenuProc.stderrBytes = 0
    submenuProc.outputOverflow = false
    submenuProc.command = node.submenuCommand.map(function(argument) {
      return MenuModel.workflowInterpolate(argument, root.workflowValues())
    })
    submenuProc.running = true
    submenuTimeout.restart()
    root.rebuildDisplay()
  }

  function invalidateDocument(reason) {
    if (documentProc.stopping) return
    documentTimeout.stop()
    root.documentGeneration += 1
    if (documentProc.running) {
      documentProc.stopping = true
      documentProc.stopGeneration = documentProc.generation
      documentKillTimer.generation = documentProc.stopGeneration
      documentProc.running = false
      documentKillTimer.restart()
    }
    root.documentLoading = false
  }

  function enterDocument(node) {
    if (!node || !node.documentCommand || node.documentCommand.length === 0
        || !root.workflowExtension || root.workflowStack.length >= root.workflowMaxDepth
        || documentProc.running || documentProc.stopping) return
    root.invalidateWorkflowAction("entered document")
    if (root.workflowNode)
      root.workflowStack = root.workflowStack.concat([{ node: root.workflowNode, context: root.workflowContext }])
    root.workflowContext = root.workflowNodeContext(node, root.workflowContext)
    root.workflowNode = { id: node.id + ".document", kind: "document", label: node.label,
      document: null }
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = false
    root.documentError = ""
    root.documentLoading = true
    root.documentGeneration += 1
    documentProc.generation = root.documentGeneration
    documentProc.extensionCapability = root.workflowExtension.capability
    documentProc.documentNodeId = root.workflowNode.id
    documentProc.collected = ""
    documentProc.stderrBytes = 0
    documentProc.outputOverflow = false
    documentProc.command = node.documentCommand.map(function(argument) {
      return MenuModel.workflowInterpolate(argument, root.workflowValues())
    })
    documentProc.running = true
    documentTimeout.restart()
    root.rebuildDisplay()
  }

  function enterWorkflow(extension) {
    if (!extension || !extension.available || extension.mode !== "workflow") return
    root.invalidateExtensionQuery("entered workflow")
    root.invalidateWorkflowAction("entered workflow")
    root.focusedExtension = null
    root.leaveFileBrowser(false)
    root.workflowActive = true
    root.workflowExtension = extension
    root.workflowStack = []
    root.workflowContext = ({})
    root.workflowNode = {
      id: "root",
      kind: "menu",
      label: extension.label,
      description: extension.description,
      items: extension.workflow.items
    }
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function leaveWorkflow() {
    root.invalidateWorkflowAction("left workflow")
    root.invalidateSubmenu("left workflow")
    root.invalidateDocument("left workflow")
    root.invalidateDynamicMenu()
    root.workflowConfirmOpen = false
    root.workflowConfirmNode = null
    root.resetFileIndex()
    root.fileBrowserActive = false
    root.directoryPickerActive = false
    root.fileBrowserExtension = null
    root.workflowActive = false
    root.workflowExtension = null
    root.workflowNode = null
    root.workflowContext = ({})
    root.workflowStack = []
    root.submenuLoading = false
    root.documentLoading = false
    root.documentError = ""
    root.dynamicMenuLoading = false
    root.workflowConfirmOpen = false
    root.workflowConfirmNode = null
    root.filterText = ""
    root.rebuildDisplay()
  }

  function showWorkflowNode(node, context, pushCurrent) {
    if (!node) return
    if (pushCurrent && root.workflowNode)
      root.workflowStack = root.workflowStack.concat([{ node: root.workflowNode, context: root.workflowContext }])
    root.resetFileIndex()
    root.fileBrowserActive = false
    root.directoryPickerActive = false
    root.fileBrowserExtension = null
    root.workflowNode = node
    root.workflowContext = root.workflowNodeContext(node, context)
    root.filterText = node.kind === "input"
      ? MenuModel.workflowInitialInput(node, root.workflowValues()) : ""
    root.selectedIndex = 0
    root.cursorActive = node.kind !== "input"
    if (node.kind === "directoryPicker") root.enterDirectoryPicker(root.workflowContext.path || "")
    else root.rebuildDisplay()
  }

  function workflowBack() {
    if (!root.workflowActive) return false
    root.invalidateWorkflowAction("workflow navigation changed")
    root.invalidateSubmenu("workflow navigation changed")
    root.invalidateDocument("workflow navigation changed")
    root.resetFileIndex()
    root.fileBrowserActive = false
    root.directoryPickerActive = false
    root.fileBrowserExtension = null
    if (root.workflowStack.length === 0) {
      root.leaveWorkflow()
      return true
    }
    var previous = root.workflowStack[root.workflowStack.length - 1]
    root.workflowStack = root.workflowStack.slice(0, root.workflowStack.length - 1)
    root.showWorkflowNode(previous.node, previous.context, false)
    return true
  }

  function activateWorkflowChild(index) {
    if (!root.workflowNode || root.workflowNode.kind !== "menu") return
    var child = root.workflowNode.items[index]
    if (!child) return
    if (child.submenuCommand && child.submenuCommand.length > 0) root.enterSubmenu(child)
    else if (child.documentCommand && child.documentCommand.length > 0) root.enterDocument(child)
    else if (child.kind === "action") root.dispatchWorkflowNode(child, "")
    else if (child.kind === "confirm") {
      root.workflowConfirmNode = child
      root.workflowConfirmOpen = true
    } else root.showWorkflowNode(child, root.workflowContext, true)
  }

  function workflowStarAction(node) {
    if (!node || !node.starAction || !node.actions) return null
    for (var i = 0; i < node.actions.length; i++)
      if (node.actions[i].id === node.starAction) return node.actions[i]
    return null
  }

  function toggleSelectedWorkflowStar() {
    var action = root.selectedWorkflowStarAction
    if (action) root.dispatchWorkflowNode(action, "", false, true)
  }

  function openWorkflowActions() {
    if (!root.workflowActive || root.fileBrowserActive || !root.workflowNode) return
    if (root.documentActive) {
      var documentActions = root.activeDocument && root.activeDocument.actions ? root.activeDocument.actions : []
      if (documentActions.length === 0) return
      root.showWorkflowNode({ id: root.workflowNode.id + ".actions", kind: "menu",
        label: root.activeDocument.title, description: "Actions", items: documentActions },
        root.workflowContext, true)
      return
    }
    if (root.workflowNode.kind !== "menu" || !root.cursorActive || root.selectedIndex < 0
        || root.selectedIndex >= root.workflowNode.items.length) return
    var child = root.selectedWorkflowNode
    if (!child || !child.actions || child.actions.length === 0) return
    root.showWorkflowNode({ id: child.id + ".actions", kind: "menu", label: child.label,
      description: "Actions", items: child.actions }, root.workflowContext, true)
  }

  function toggleSelectedDynamicStar() {
    var entry = root.selectedDynamicSearchEntry
    var action = root.selectedDynamicStarAction
    if (!entry || !action) return
    var extension = root.extensionByCapability(entry.capability)
    if (!extension || !extension.available || extension.id !== entry.extensionId) return
    root.dispatchBackgroundAction(extension, action, "")
  }

  function openDynamicSearchActions() {
    var entry = root.selectedDynamicSearchEntry
    if (!entry || !entry.node.actions || entry.node.actions.length === 0) return
    var extension = root.extensionByCapability(entry.capability)
    if (!extension || !extension.available || extension.id !== entry.extensionId) return
    root.workflowActive = true
    root.workflowExtension = extension
    root.workflowContext = ({ extensionDir: extension.sourceDir })
    root.workflowStack = []
    root.workflowNode = { id: entry.node.id + ".actions", kind: "menu", label: entry.node.label,
      description: "Actions", items: entry.node.actions }
    root.filterText = ""
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  function boundedBackgroundDiagnostic(value) {
    var text = String(value || "").replace(/[\r\n\0]/g, " ")
    return text.substring(0, root.backgroundDiagnosticTextLimit)
  }

  function dispatchBackgroundAction(extension, node, input) {
    if (!extension || !node) return
    var values = Object.assign({}, root.workflowContext || ({}), { extensionDir: extension.sourceDir, input: input })
    var command = MenuModel.workflowCommand(node, input, values)
    if (!MenuModel.workflowBackgroundEligible(node, command)) return
    if (backgroundActionProc.running || backgroundActionProc.stopping) {
      console.warn("Omalaunch: background action is busy; ignored " + root.boundedBackgroundDiagnostic(node.id))
      return
    }
    root.backgroundActionGeneration += 1
    backgroundActionProc.generation = root.backgroundActionGeneration
    backgroundActionProc.extensionCapability = extension.capability
    backgroundActionProc.refreshExtensions = node.refreshExtensions
    backgroundActionProc.closeAfter = node.closeOnSuccess
    backgroundActionProc.actionId = root.boundedBackgroundDiagnostic(node.id)
    backgroundActionProc.usageItemId = MenuModel.dynamicMenuUsageItemId(extension, node)
    backgroundActionProc.command = command
    backgroundActionProc.running = true
    backgroundActionTimeout.restart()
  }

  function invalidateBackgroundAction(reason) {
    if (backgroundActionProc.stopping || !backgroundActionProc.running) return
    root.backgroundActionGeneration += 1
    backgroundActionTimeout.stop()
    backgroundActionProc.stopping = true
    backgroundActionProc.stopGeneration = backgroundActionProc.generation
    backgroundActionKillTimer.generation = backgroundActionProc.stopGeneration
    backgroundActionProc.running = false
    backgroundActionKillTimer.restart()
  }

  function dispatchWorkflowNode(node, input, returnToRoot, backgroundRequested) {
    if (!node) return
    var transition = node.kind === "input" ? MenuModel.workflowInputTransition(node, input, root.workflowContext)
      : { node: node.next, context: root.workflowContext }
    if (!transition) return
    var command = MenuModel.workflowCommand(node, input, root.workflowValues({ input: input }))
    if (command.length === 0) return
    if (backgroundRequested === true && MenuModel.workflowBackgroundEligible(node, command)) {
      root.dispatchBackgroundAction(root.workflowExtension, node, input)
      return
    }
    if (workflowActionProc.running || workflowActionProc.stopping) return
    if (MenuModel.workflowClosesOnDispatch(node, command)) {
      Quickshell.execDetached(command)
      root.closeWorkflowAfterDispatch()
      return
    }
    root.workflowGeneration += 1
    workflowActionProc.generation = root.workflowGeneration
    workflowActionProc.extensionCapability = root.workflowExtension.capability
    workflowActionProc.usageItemId = MenuModel.dynamicMenuUsageItemId(root.workflowExtension, node)
    workflowActionProc.nextNode = node.next
    workflowActionProc.nextContext = transition.context
    workflowActionProc.refreshExtensions = node.refreshExtensions
    workflowActionProc.refreshDynamicMenu = root.workflowExtension.mode === "menu" && !node.next && !node.refreshExtensions && !node.closeOnSuccess
    workflowActionProc.nextBackSteps = node.nextBackSteps
    workflowActionProc.closeAfter = node.closeOnSuccess || (root.workflowExtension.mode !== "menu" && !node.next)
    workflowActionProc.returnToRoot = returnToRoot === true
    console.warn("Omalaunch action dispatch: " + JSON.stringify(command))
    workflowActionProc.command = command
    workflowActionProc.running = true
    workflowActionTimeout.restart()
  }

  function enterDirectoryPicker(startPath) {
    root.fileBrowserShowHidden = false
    root.directoryPickerActive = true
    root.fileBrowserActive = true
    root.fileBrowserExtension = root.activeFilesExtension()
    var requestedPath = MenuModel.normalizeFavoritePath(startPath)
    root.fileBrowserPath = requestedPath || Quickshell.env("HOME")
    root.filterText = ""
    root.fileEntries = []
    root.selectedIndex = 0
    root.cursorActive = true
    root.scheduleFileScan()
  }

  function selectWorkflowDirectory(path) {
    if (!root.directoryPickerActive || !root.workflowNode || !root.workflowNode.next) return
    var transition = MenuModel.workflowDirectoryTransition(root.workflowNode, path, root.workflowContext)
    if (!transition) return
    root.workflowStack = root.workflowStack.concat([{ node: root.workflowNode, context: transition.context }])
    root.showWorkflowNode(transition.node, transition.context, false)
  }

  function submitWorkflowInput() {
    var node = root.workflowNode
    if (!root.workflowActive || !node || node.kind !== "input" || workflowActionProc.running || workflowActionProc.stopping) return
    var value = String(root.filterText || "").substring(0, node.maxLength)
    var transition = MenuModel.workflowInputTransition(node, value, root.workflowContext)
    // Validation happens before any generation change or launcher close.
    if (!transition) return
    var command = MenuModel.workflowCommand(node, value, root.workflowValues({ input: value }))
    if (command.length === 0) {
      if (node.next) root.showWorkflowNode(node.next, transition.context, true)
      return
    }
    root.dispatchWorkflowNode(node, value)
  }

  function invalidateWorkflowAction(reason) {
    if (workflowActionProc.stopping) return
    if (workflowActionProc.generation <= 0 && !workflowActionProc.running) return
    root.workflowGeneration += 1
    workflowActionTimeout.stop()
    workflowActionProc.generation = 0
    workflowActionProc.nextNode = null
    workflowActionProc.nextContext = ({})
    workflowActionProc.refreshExtensions = false
    workflowActionProc.refreshDynamicMenu = false
    workflowActionProc.nextBackSteps = 0
    workflowActionProc.closeAfter = false
    workflowActionProc.usageItemId = ""
    if (workflowActionProc.running) {
      // `running = false` is Quickshell's supported SIGTERM path. Keep the
      // Process reserved during a short grace period; a generation-matched
      // timer escalates the same direct child with SIGKILL if it does not exit.
      workflowActionProc.stopping = true
      workflowActionProc.stopGeneration = root.workflowGeneration
      workflowActionKillTimer.generation = workflowActionProc.stopGeneration
      workflowActionProc.running = false
      workflowActionKillTimer.restart()
    }
  }

  function closeWorkflowAfterDispatch() {
    root.cancel()
  }

  function filesExtensionForCapability(capability) {
    for (var i = 0; i < root.extensions.length; i++) {
      var extension = root.extensions[i]
      if (extension && extension.mode === "files" && extension.capability === capability) return extension
    }
    return null
  }

  function activeFilesExtension() {
    return root.filesExtensionForCapability("files")
  }

  function fileFavoriteId(path, type) {
    if (!root.fileBrowserExtension) return ""
    return MenuModel.fileFavoriteId(path, type, root.fileBrowserExtension.capability)
  }

  function fileFavoriteIds(path, type, capability) {
    var ids = [MenuModel.fileFavoriteId(path, type, capability)]
    if (capability === "files") ids.push(MenuModel.legacyFileFavoriteId(path, type))
    return ids
  }

  function isFileFavoriteStarred(path, type) {
    if (!root.fileBrowserExtension) return false
    var ids = root.fileFavoriteIds(path, type, root.fileBrowserExtension.capability)
    for (var i = 0; i < ids.length; i++)
      if (ids[i] && favorites.isStarred(ids[i])) return true
    return false
  }

  function toggleFileFavorite(path, type) {
    if (!root.fileBrowserExtension) return
    var ids = root.fileFavoriteIds(path, type, root.fileBrowserExtension.capability)
    for (var i = 0; i < ids.length; i++) {
      if (!ids[i] || !favorites.isStarred(ids[i])) continue
      favorites.removeIds(ids)
      return
    }
    favorites.toggle(ids[0])
  }

  function unstarFileFavorite(favorite) {
    if (!favorite) return
    favorites.removeIds(root.fileFavoriteIds(favorite.path, favorite.type, favorite.capability))
  }

  function enterFileBrowser(extension, startPath) {
    if (!extension || !extension.available) return
    root.invalidateExtensionQuery("entered file browser")
    root.focusedExtension = null
    root.resetFileIndex()
    root.fileBrowserActive = true
    root.fileBrowserShowHidden = false
    root.fileBrowserExtension = extension
    var requestedPath = MenuModel.normalizeFavoritePath(startPath)
    root.fileBrowserPath = requestedPath || (extension.root === "~" ? Quickshell.env("HOME") : extension.root)
    root.filterText = ""
    root.fileEntries = []
    root.selectedIndex = 0
    root.cursorActive = true
    root.scheduleFileScan()
  }

  function leaveFileBrowser(rebuild) {
    root.resetFileIndex()
    root.actionPanelActive = false
    root.actionPanelFile = null
    root.fileBrowserActive = false
    root.directoryPickerActive = false
    root.fileBrowserExtension = null
    root.fileBrowserPath = ""
    root.fileEntries = []
    root.filterText = ""
    if (rebuild !== false) root.rebuildDisplay()
  }

  function parentPath(path) {
    var value = String(path || "").replace(/\/+$/, "")
    if (!value || value === "/") return "/"
    var slash = value.lastIndexOf("/")
    return slash <= 0 ? "/" : value.substring(0, slash)
  }

  function removeFileIndex(path) {
    if (path) Quickshell.execDetached(["rm", "-f", "--", path])
  }

  function resetFileIndex() {
    root.fileIndexSerial += 1
    root.removeFileIndex(root.fileIndexPath)
    root.fileIndexPath = ""
    root.fileIndexRoot = ""
    root.fileIndexReady = false
    root.fileIndexBuiltAt = 0
    if (fileIndexProc.running && !fileIndexProc.stopping) {
      fileIndexProc.stopping = true
      fileIndexProc.running = false
    }
  }

  function includeGitIgnoredFiles() {
    var extension = root.extensionByCapability("files")
    return !!(extension && extension.config && extension.config.includeGitIgnored === true)
  }

  function toggleHiddenFiles() {
    root.fileBrowserShowHidden = !root.fileBrowserShowHidden
    root.resetFileIndex()
    root.fileEntries = []
    root.selectedIndex = 0
    root.scheduleFileScan(true)
  }

  function fileScanOptions() {
    return (root.includeGitIgnoredFiles() ? ["--include-git-ignored"] : [])
      .concat(root.fileBrowserShowHidden ? ["--hidden"] : [])
  }

  function startFileIndex(path) {
    // Process command and metadata must stay immutable until onExited. Keep a
    // build for the requested root alive while typing; only a different root
    // is allowed to stop it.
    if (fileIndexProc.running || fileIndexProc.stopping) {
      if (fileIndexProc.indexRoot === path) return
      if (fileIndexProc.running && !fileIndexProc.stopping) {
        fileIndexProc.stopping = true
        fileIndexProc.running = false
      }
      return
    }
    root.removeFileIndex(root.fileIndexPath)
    root.fileIndexSerial += 1
    root.fileIndexPath = root.fileIndexPathPrefix + "-" + root.fileIndexSerial + ".nul"
    root.fileIndexRoot = path
    root.fileIndexReady = false
    root.fileIndexBuiltAt = 0
    fileIndexProc.revision = root.fileIndexSerial
    fileIndexProc.indexRoot = path
    fileIndexProc.indexPath = root.fileIndexPath
    fileIndexProc.command = ["python", root.fileIndexHelper, root.directoryPickerActive ? "index-dirs" : "index"]
      .concat(root.fileScanOptions()).concat(["--", path, fileIndexProc.indexPath])
    fileIndexProc.running = true
  }

  function scheduleFileScan(immediate) {
    root.fileScanSerial += 1
    fileScanTimer.interval = immediate === true ? 0 : 120
    fileScanTimer.restart()
    if (fileScanProc.running && !fileScanProc.stopping) {
      fileScanProc.stopping = true
      fileScanProc.running = false
    }
    if (root.fileIndexRoot && root.fileIndexRoot !== root.fileBrowserPath) root.resetFileIndex()
  }

  function rebuildFileDisplay() {
    displayModel.clear()
    root.searchDivider = false
    if (root.directoryPickerActive) {
      var selectItem = root.normalizeItem("workflow.directory.select", {
        icon: "✓",
        label: "Select this directory",
        description: root.fileBrowserPath,
        action: root.fileBrowserPath
      })
      displayModel.append(root.displayRow(selectItem, root.fileBrowserPath, -1))
    }
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
      row.starred = !root.directoryPickerActive && root.isFileFavoriteStarred(entry.path, entry.type)
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
      {
        id: "toggle-star",
        icon: "★",
        label: root.isFileFavoriteStarred(root.actionPanelFile.path, root.actionPanelFile.type)
          ? "Unstar" : "Star"
      },
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
      itemId: row.itemId,
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
    if (action === "toggle-star") {
      var selectedItemId = root.actionPanelFile.itemId
      var selectedType = root.actionPanelFile.type
      var previousIndex = root.actionPanelFile.index
      root.actionPanelActive = false
      root.actionPanelFile = null
      root.selectedIndex = previousIndex
      root.pendingStarSelectionId = selectedItemId
      root.toggleFileFavorite(path, selectedType)
      return
    }
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
    root.resetFileIndex()
    root.opened = false
    root.runAction(shellAction)
  }

  function normalizeItem(id, raw) {
    return MenuModel.normalizeItem(id, raw)
  }

  function rebuildItemMetadata() {
    root.itemMetadata = MenuModel.buildItemMetadata(root.items, root.itemOrder, root.whenResults)
  }

  function metadataFor(id) {
    return root.itemMetadata[id] || null
  }

  function parseMenuJsonc(raw) {
    return MenuModel.parseMenuJsonc(raw)
  }

  function parseMenuJsoncSnapshot(raw) {
    return MenuModel.parseMenuJsoncSnapshot(raw)
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
    nextItems.extensions = root.normalizeItem("extensions", {
      icon: "󰏗",
      label: "Extensions",
      title: "Extensions"
    })
    nextItems.settings = root.normalizeItem("settings", {
      icon: "󰒓",
      label: "Omalaunch Settings",
      title: "Omalaunch Settings"
    })
    nextItems["settings.font-size"] = root.normalizeItem("settings.font-size", {
      parent: "settings",
      kind: "menu",
      icon: "󰛖",
      label: "Font Size",
      title: "Font Size"
    })
    var fontOptions = [
      ["compact", "Compact", "bodySmall"],
      ["small", "Small", "body"],
      ["default", "Default", "title"],
      ["large", "Large", "heading"],
      ["extra-large", "Extra Large", "display"]
    ]
    for (var optionIndex = 0; optionIndex < fontOptions.length; optionIndex++) {
      var option = fontOptions[optionIndex]
      nextItems["settings.font-size." + option[0]] = root.normalizeItem("settings.font-size." + option[0], {
        parent: "settings.font-size",
        kind: "action",
        icon: "·",
        label: option[1],
        description: option[2],
        action: option[2]
      })
    }
    for (var id in nextItems) {
      if (id === "root" || id === "omarchy" || id === "extensions" || id === "settings") continue
      if (nextItems[id].parent === "root") nextItems[id] = Object.assign({}, nextItems[id], { parent: "omarchy" })
    }
    var nextOrder = mergedMenu.itemOrder.filter(function(id) {
      return id !== "omarchy" && id !== "extensions" && id !== "settings"
    })
    var rootIndex = nextOrder.indexOf("root")
    var insertAt = rootIndex >= 0 ? rootIndex + 1 : 0
    nextOrder.splice(insertAt, 0, "omarchy", "extensions", "settings", "settings.font-size")
    for (var fontOptionIndex = 0; fontOptionIndex < fontOptions.length; fontOptionIndex++)
      nextOrder.splice(insertAt + 4 + fontOptionIndex, 0, "settings.font-size." + fontOptions[fontOptionIndex][0])
    root.items = nextItems
    root.itemOrder = nextOrder
    root.rebuildItemMetadata()
    root.rowsLoaded = true
    root.evaluateGuards(true)
    if (root.routePendingForMenuSources) {
      var pendingRoute = root.pendingInitialMenu
      root.routePendingForMenuSources = false
      root.openRoute(pendingRoute)
      return
    }
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim()) root.loadProvidersForSearch()
        else {
          root.loadProviderForMenu(root.activeMenu)
          // Root includes favorite applications and global search starts here,
          // so preserve openExistingMenu's Apps prefetch after each generation.
          if (root.activeMenu === "root") root.loadProviderForMenu("apps")
        }
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
    // An empty replacement removes rows from a detached AppLibrary instead of
    // leaving stale, non-launchable applications in search and favorites.
    var rows = root.appLibrary ? root.appLibrary.sortedEntries("") : []
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
    root.rebuildItemMetadata()
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
    root.rebuildItemMetadata()
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
    var metadata = root.metadataFor(id)
    return metadata ? metadata.depth : MenuModel.depthFor(root.items, id)
  }

  function pathFor(id) {
    var metadata = root.metadataFor(id)
    return metadata ? metadata.path : MenuModel.pathFor(root.items, id)
  }

  function parentPathFor(id) {
    return MenuModel.parentPathFor(root.items, id, root.itemMetadata)
  }

  function isDescendantOf(id, ancestorId) {
    return MenuModel.isDescendantOf(root.items, id, ancestorId, root.itemMetadata)
  }

  function childCount(id) {
    var metadata = root.metadataFor(id)
    return metadata ? metadata.childCount : MenuModel.childCount(root.items, root.itemOrder, id)
  }

  // Guarded items are hidden when their `when:` evaluates false. Static
  // submenus are also hidden when none of their descendants are visible;
  // provider-backed menus stay visible because their rows load on demand.
  function isVisible(entry) {
    var metadata = entry ? root.metadataFor(entry.id) : null
    return metadata ? metadata.visible : MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
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
    var metadata = entry ? root.metadataFor(entry.id) : null
    return MenuModel.matchesQuery(entry, query, metadata ? metadata.visible : root.isVisible(entry), metadata)
  }

  function searchScore(entry, query) {
    return MenuModel.searchScore(root.items, entry, query, root.metadataFor(entry.id))
  }

  function displayRow(entry, detail, score, section) {
    return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults,
      entry, detail, score, section, root.metadataFor(entry.id))
  }

  function rebuildDmenuDisplay() {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      return
    }

    var query = root.filterText.trim().toLowerCase()
    var appended = 0
    for (var i = 0; i < root.dmenuRows.length && appended < root.maxDisplayedResults; i++) {
      var option = root.dmenuRows[i]
      if (query && option.searchText.indexOf(query) < 0) continue
      displayModel.append({
        itemId: "dmenu." + option.index,
        kind: "dmenu",
        icon: option.icon,
        iconFont: "",
        trailingIcon: "",
        trailingText: "",
        badge: "",
        badgeTone: "neutral",
        appIcon: "",
        appId: "",
        label: option.label,
        target: "",
        detail: option.detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: "",
        starred: false
      })
      appended += 1
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
    if (root.workflowActive) {
      displayModel.clear()
      root.searchDivider = false
      if (root.workflowNode && root.workflowNode.kind === "menu") {
        var workflowQuery = MenuModel.prepareSearchQuery(root.filterText.trim())
        for (var workflowIndex = 0; workflowIndex < root.workflowNode.items.length; workflowIndex++) {
          var workflowChild = root.workflowNode.items[workflowIndex]
          var workflowItem = root.normalizeItem("workflow.node." + workflowIndex, {
            icon: workflowChild.icon,
            iconFont: workflowChild.iconFont,
            trailingIcon: workflowChild.trailingIcon,
            trailingText: workflowChild.trailingText,
            badge: workflowChild.badge,
            badgeTone: workflowChild.badgeTone,
            label: root.workflowText(workflowChild.label),
            description: root.workflowText(workflowChild.description),
            aliases: workflowChild.aliases,
            action: String(workflowIndex)
          })
          if (workflowQuery && !MenuModel.matchesQuery(workflowItem, workflowQuery, true)) continue
          if (workflowChild.kind === "menu" || workflowChild.kind === "directoryPicker") workflowItem.kind = "menu"
          var workflowRow = root.displayRow(workflowItem, workflowItem.description, workflowIndex)
          workflowRow.starred = workflowChild.starred
          displayModel.append(workflowRow)
        }
      }
      root.layoutSerial += 1
      root.selectedIndex = displayModel.count > 0 ? Math.min(root.selectedIndex, displayModel.count - 1) : 0
      root.cursorActive = displayModel.count > 0
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
      var diagnosticRows = []
      var preparedQuery = MenuModel.prepareSearchQuery(query)
      var settingsSearchScoped = root.settingsPageActive()
      var liveResult = !settingsSearchScoped && root.extensionQuery === root.effectiveExtensionQuery() ? root.extensionResult : ""
      for (var i = 0; !root.focusedExtension && i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (MenuModel.isSearchExcluded(root.items, entry.id, root.searchExcludedRoots, root.itemMetadata)) continue
        if (settingsSearchScoped ? entry.parent !== active : !root.isDescendantOf(entry.id, active)) continue
        if (!root.matchesQuery(entry, preparedQuery)) continue

        var detail = root.parentPathFor(entry.id)
        var metadata = root.metadataFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, preparedQuery))
        row.starred = favorites.isStarred(row.itemId)
        row.matchPriority = MenuModel.searchMatchPriority(entry, preparedQuery, metadata)
        row.usageCount = usage.count(row.itemId)
        row.lastUsedAt = usage.lastUsedAt(row.itemId)
        rows.push(row)
      }

      // Keep the fixed Extensions directory searchable even while dynamic
      // catalog and global-search snapshots rebuild the ordinary item order.
      if (!root.focusedExtension && active === "root") {
        var extensionsDirectory = root.item("extensions")
        var extensionsDirectorySeen = false
        for (var extensionsSeenIndex = 0; extensionsSeenIndex < rows.length; extensionsSeenIndex++)
          if (rows[extensionsSeenIndex].itemId === "extensions") { extensionsDirectorySeen = true; break }
        if (!extensionsDirectorySeen && extensionsDirectory && MenuModel.matchesQuery(extensionsDirectory, preparedQuery, true)) {
          var extensionsDirectoryRow = root.displayRow(extensionsDirectory, extensionsDirectory.description, 0)
          extensionsDirectoryRow.matchPriority = MenuModel.searchMatchPriority(extensionsDirectory, preparedQuery)
          rows.push(extensionsDirectoryRow)
        }
      }

      // File favorites are synthetic starting-view rows rather than members of
      // the menu tree, so add matching ones explicitly during global search.
      if (!root.focusedExtension && active === "root") {
        var searchFavoriteIds = Object.keys(favorites.starredIds)
        var seenSearchFileFavorites = ({})
        for (var searchFavoriteIndex = 0; searchFavoriteIndex < searchFavoriteIds.length; searchFavoriteIndex++) {
          var searchFavorite = MenuModel.fileFavorite(searchFavoriteIds[searchFavoriteIndex])
          var searchFavoriteItem = MenuModel.fileFavoriteItem(searchFavoriteIds[searchFavoriteIndex])
          if (!searchFavorite || !searchFavoriteItem || seenSearchFileFavorites["$" + searchFavoriteItem.id]) continue
          seenSearchFileFavorites["$" + searchFavoriteItem.id] = true
          if (!MenuModel.matchesFileFavoriteQuery(searchFavoriteItem, preparedQuery)) continue
          searchFavoriteItem.icon = searchFavorite.type === "directory" ? "󰉋" : "󰈔"
          var searchFavoriteRow = root.displayRow(searchFavoriteItem, searchFavorite.path, 0)
          searchFavoriteRow.path = searchFavorite.path
          searchFavoriteRow.starred = true
          searchFavoriteRow.matchPriority = MenuModel.searchMatchPriority(searchFavoriteItem, preparedQuery)
          rows.push(searchFavoriteRow)
        }
      }

      if (!root.focusedExtension && active === "root") {
        for (var dynamicSearchIndex = 0; dynamicSearchIndex < root.dynamicMenuSearchSnapshot.length; dynamicSearchIndex++) {
          var dynamicSearchEntry = root.dynamicMenuSearchSnapshot[dynamicSearchIndex]
          if (!MenuModel.matchesQuery(dynamicSearchEntry.item, preparedQuery, true)) continue
          var dynamicSearchRow = root.displayRow(dynamicSearchEntry.item, dynamicSearchEntry.item.description, 0)
          dynamicSearchRow.starred = dynamicSearchEntry.node.starred
          dynamicSearchRow.matchPriority = MenuModel.searchMatchPriority(dynamicSearchEntry.item, preparedQuery)
          var dynamicUsageId = MenuModel.dynamicMenuUsageItemId(
            root.extensionById(dynamicSearchEntry.extensionId), dynamicSearchEntry.node)
          dynamicSearchRow.usageCount = usage.count(dynamicUsageId)
          dynamicSearchRow.lastUsedAt = usage.lastUsedAt(dynamicUsageId)
          rows.push(dynamicSearchRow)
        }
      }

      var matchedExtensionRoots = ({})
      if (!root.focusedExtension && (active === "root" || active === "extensions")) {
        for (var searchExtensionIndex = 0; searchExtensionIndex < root.extensions.length; searchExtensionIndex++) {
          var searchExtension = root.extensions[searchExtensionIndex]
          var searchExtensionItem = MenuModel.extensionRootItem(searchExtension)
          if (!searchExtensionItem || !MenuModel.matchesQuery(searchExtensionItem, preparedQuery, true)) continue
          var searchExtensionRow = root.displayRow(searchExtensionItem, searchExtensionItem.description,
            MenuModel.searchScore(({ extensions: root.item("extensions") }), searchExtensionItem, preparedQuery))
          searchExtensionRow.starred = favorites.isStarred(searchExtensionRow.itemId)
          searchExtensionRow.matchPriority = MenuModel.searchMatchPriority(searchExtensionItem, preparedQuery)
          searchExtensionRow.usageCount = usage.count(searchExtensionRow.itemId)
          searchExtensionRow.lastUsedAt = usage.lastUsedAt(searchExtensionRow.itemId)
          matchedExtensionRoots["$" + searchExtension.capability] = true
          rows.push(searchExtensionRow)
        }
      }

      var activeExtensionCatalog = settingsSearchScoped ? []
        : (root.focusedExtension ? [root.focusedExtension] : root.extensions)
      // A focused prefix extension has a hidden global prefix and one literal
      // prompt action. It must not rediscover its own root/suggestion rows.
      var focusedPrefix = MenuModel.focusedPrefixMatch(root.focusedExtension, query)
      if (focusedPrefix) {
        var focusedPrefixItem = root.normalizeItem("extension.focused.prefix", {
          icon: focusedPrefix.extension.icon,
          iconFont: focusedPrefix.extension.iconFont,
          label: focusedPrefix.extension.label + ": " + focusedPrefix.prompt,
          description: focusedPrefix.extension.description,
          action: root.extensionAction(focusedPrefix.extension, focusedPrefix.prompt)
        })
        var focusedPrefixRow = root.displayRow(focusedPrefixItem, focusedPrefixItem.description, -1)
        focusedPrefixRow.matchPriority = MenuModel.extensionResultPriority()
        rows.push(focusedPrefixRow)
      }
      // Focused extension inputs already establish which provider owns the
      // query; showing its ordinary prefix suggestion/action row duplicates
      // the dedicated result surface.
      var extensionSuggestions = root.focusedExtension ? [] : MenuModel.suggestExtensions(activeExtensionCatalog, query)
      for (var suggestionIndex = extensionSuggestions.length - 1; suggestionIndex >= 0; suggestionIndex--) {
        var suggestion = extensionSuggestions[suggestionIndex]
        var suggestedExtension = suggestion.extension
        if (matchedExtensionRoots["$" + suggestedExtension.capability]) continue
        var suggestionDetail = suggestedExtension.available
          ? suggestedExtension.description
          : MenuModel.unavailableExtensionDetail(suggestedExtension)
        var suggestionId = suggestedExtension.available ? "extension.prepare." : "extension.unavailable."
        var suggestionItem = root.normalizeItem(suggestionId + suggestedExtension.id, {
          icon: suggestedExtension.icon,
          iconFont: suggestedExtension.iconFont,
          label: suggestedExtension.label,
          description: suggestionDetail,
          action: suggestedExtension.available ? suggestion.prefix + " " : ""
        })
        var suggestionRow = root.displayRow(suggestionItem, suggestionDetail, -3)
        suggestionRow.matchPriority = MenuModel.extensionSuggestionPriority(suggestion, query)
        if (suggestedExtension.available) rows.push(suggestionRow)
        else diagnosticRows.push(suggestionRow)
      }

      var extensionMatches = root.focusedExtension ? [] : MenuModel.matchExtensions(activeExtensionCatalog, query)
      for (var extensionIndex = extensionMatches.length - 1; extensionIndex >= 0; extensionIndex--) {
        var extensionMatch = extensionMatches[extensionIndex]
        var extension = extensionMatch.extension
        var extensionDetail = extension.available
          ? extension.description
          : MenuModel.unavailableExtensionDetail(extension)
        var extensionId = extension.available ? "extension." : "extension.unavailable."
        var extensionItem = root.normalizeItem(extensionId + extension.id, {
          icon: extension.icon,
          iconFont: extension.iconFont,
          label: extension.label + ": " + extensionMatch.prompt,
          description: extensionDetail,
          action: extension.available ? root.extensionAction(extension, extensionMatch.prompt) : ""
        })
        var extensionRow = root.displayRow(extensionItem, extensionDetail, -2)
        extensionRow.matchPriority = MenuModel.extensionMatchPriority(extension)
        if (extension.available) rows.push(extensionRow)
        else diagnosticRows.push(extensionRow)
      }

      if (!settingsSearchScoped && root.unavailableResultExtension) {
        var unavailableDetail = MenuModel.unavailableExtensionDetail(root.unavailableResultExtension)
        var unavailableItem = root.normalizeItem("extension.unavailable." + root.unavailableResultExtension.id, {
          icon: root.unavailableResultExtension.icon,
          iconFont: root.unavailableResultExtension.iconFont,
          label: root.unavailableResultExtension.label + " unavailable",
          description: unavailableDetail
        })
        var unavailableRow = root.displayRow(unavailableItem, unavailableDetail, -1)
        unavailableRow.matchPriority = 0
        diagnosticRows.push(unavailableRow)
      }

      if (liveResult && root.resultExtension) {
        var resultItem = root.normalizeItem("extension.result", {
          icon: root.resultExtension.icon,
          iconFont: root.resultExtension.iconFont,
          label: "= " + liveResult,
          description: root.resultExtension.description,
          action: root.shellCommand(root.resultExtension.resultCommand, { result: liveResult, query: query })
        })
        var resultRow = root.displayRow(resultItem, root.resultExtension.description, -1)
        resultRow.matchPriority = MenuModel.extensionResultPriority()
        rows.push(resultRow)
      }

      // Rank normal item and extension rows together. Diagnostic rows reserve
      // space at the bottom so dependency/setup guidance survives the cap.
      rows = MenuModel.rankSearchRows(rows, diagnosticRows, root.maxDisplayedResults)
    } else if (root.focusedExtension) {
      // A focused query extension is an input surface, not the Extensions
      // directory with an invisible focus change. Keep its initial result list
      // empty until the user enters a query.
    } else {
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.id === "root") continue
        if (active === "root") {
          if (child.id !== "omarchy" && child.id !== "extensions" && !favorites.isStarred(child.id)) continue
        } else if (child.parent !== active) continue
        // Extension roots are generated at runtime rather than represented as
        // static menu children, so the ordinary empty-menu visibility check
        // cannot determine whether this directory has entries.
        if (!root.isVisible(child) && !(child.id === "extensions" && root.extensions.length > 0)) continue
        var childDetail = active === "root" ? root.parentPathFor(child.id) : child.description
        var childRow = root.displayRow(child, childDetail, child.order)
        childRow.starred = favorites.isStarred(childRow.itemId)
        rows.push(childRow)
      }

      if (active === "root" || active === "extensions") {
        var extensionRootRows = []
        for (var extensionRootIndex = 0; extensionRootIndex < root.extensions.length; extensionRootIndex++) {
          var listedExtension = root.extensions[extensionRootIndex]
          var listedExtensionItem = MenuModel.extensionRootItem(listedExtension)
          if (!listedExtensionItem) continue
          var listedExtensionRow = root.displayRow(listedExtensionItem, listedExtensionItem.description, extensionRootIndex)
          listedExtensionRow.starred = favorites.isStarred(listedExtensionRow.itemId)
          if (active === "extensions" || listedExtensionRow.starred) extensionRootRows.push(listedExtensionRow)
        }
        extensionRootRows = MenuModel.sortExtensionRootRows(extensionRootRows)
        rows = rows.concat(extensionRootRows)
      }

      if (active === "root") {
        for (var starredDynamicIndex = 0; starredDynamicIndex < root.dynamicMenuSearchSnapshot.length; starredDynamicIndex++) {
          var starredDynamicEntry = root.dynamicMenuSearchSnapshot[starredDynamicIndex]
          if (!starredDynamicEntry.node.starred) continue
          var starredDynamicRow = root.displayRow(starredDynamicEntry.item, starredDynamicEntry.item.description, 0)
          starredDynamicRow.starred = true
          rows.push(starredDynamicRow)
        }

        var favoriteIds = Object.keys(favorites.starredIds)
        var seenFileFavorites = ({})
        for (var favoriteIndex = 0; favoriteIndex < favoriteIds.length; favoriteIndex++) {
          var favorite = MenuModel.fileFavorite(favoriteIds[favoriteIndex])
          var favoriteItem = MenuModel.fileFavoriteItem(favoriteIds[favoriteIndex])
          if (!favorite || !favoriteItem || seenFileFavorites["$" + favoriteItem.id]) continue
          seenFileFavorites["$" + favoriteItem.id] = true
          favoriteItem.icon = favorite.type === "directory" ? "󰉋" : "󰈔"
          var favoriteRow = root.displayRow(favoriteItem, favorite.path, favoriteItem.order || 0)
          favoriteRow.starred = true
          rows.push(favoriteRow)
        }

        var setupExtension = MenuModel.firstSetupExtension(root.extensions)
        if (setupExtension) {
          var dependencySetup = MenuModel.dependencySetup(setupExtension)
          var setupItem = root.normalizeItem("dependency.setup." + setupExtension.id, {
            icon: setupExtension.icon,
            iconFont: setupExtension.iconFont,
            label: "Enable Calculator & Currency",
            description: "Install " + dependencySetup.packageName + " · Press Enter to review"
          })
          rows.push(root.displayRow(setupItem, setupItem.description, -1))
        }

        rows.sort(function(a, b) {
          if (a.itemId === "omarchy" || b.itemId === "omarchy") return a.itemId === "omarchy" ? -1 : 1
          if (a.itemId === "extensions" || b.itemId === "extensions") return a.itemId === "extensions" ? -1 : 1
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

    if (root.focusedExtension) {
      var focusedActionId = root.focusedExtension.mode === "prefix" ? "extension.focused.prefix" : "extension.result"
      var hasResultRow = false
      for (var focusedRowIndex = 0; focusedRowIndex < rows.length; focusedRowIndex++) {
        if (rows[focusedRowIndex].itemId === focusedActionId) {
          hasResultRow = true
          break
        }
      }
      if (!hasResultRow) {
        var prefixMode = root.focusedExtension.mode === "prefix"
        var pendingResultItem = root.normalizeItem("extension.result.pending", {
          icon: root.focusedExtension.icon,
          iconFont: root.focusedExtension.iconFont,
          label: prefixMode ? root.focusedExtension.label : "=",
          description: prefixMode ? "Enter a prompt" : "Result will appear here"
        })
        rows.unshift(root.displayRow(pendingResultItem, pendingResultItem.description, -1))
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

  function settingsPageActive() {
    return root.activeMenu === "settings" || root.activeMenu.indexOf("settings.") === 0
  }

  function setFilter(nextFilter) {
    if (root.actionPanelActive) return
    if (root.workflowActive && root.workflowNode && root.workflowNode.kind === "input")
      nextFilter = String(nextFilter || "").substring(0, root.workflowNode.maxLength)
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = root.mode !== "input"
    root.disarmPointer()
    if (root.fileBrowserActive) {
      // Keep the current rows visible while the debounced scan runs. Rebuilding
      // the same model here made every keystroke pay for up to 100 stale rows,
      // only to replace them again when the process completed.
      root.scheduleFileScan()
      return
    }
    if (!root.dmenuActive && root.filterText.trim() && !root.settingsPageActive()) root.loadProvidersForSearch()
    root.rebuildDisplay()
    if (root.settingsPageActive()) root.invalidateExtensionQuery("settings search is locally scoped")
    else root.scheduleExtensionQuery()
  }

  function openSettings() {
    root.resetForOpen()
    root.openRoute("settings")
  }

  function isFontSizeSetting(id) {
    return String(id || "").indexOf("settings.font-size.") === 0
  }

  function setMenuItemFontClass(fontClass) {
    root.settingsFeedback = "Saving…"
    if (settingsProc.running) {
      settingsProc.queuedFontClass = fontClass
      return
    }
    settingsProc.pendingFontClass = fontClass
    settingsProc.command = [root.configHelper, "set-font-class", fontClass]
    settingsProc.running = true
  }

  function setActiveMenu(id, pushHistory, fromPointer) {
    if (!root.item(id)) id = "root"
    root.invalidateExtensionQuery("active menu changed")
    root.focusedExtension = null
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
    var dynamicSearchEntry = root.dynamicMenuSearchEntry(row.itemId)
    if (dynamicSearchEntry) {
      var dynamicSearchExtension = root.extensionByCapability(dynamicSearchEntry.capability)
      if (!dynamicSearchExtension || !dynamicSearchExtension.available
          || dynamicSearchExtension.id !== dynamicSearchEntry.extensionId) return
      root.workflowActive = true
      root.workflowExtension = dynamicSearchExtension
      root.workflowContext = ({ extensionDir: dynamicSearchExtension.sourceDir })
      root.workflowStack = []
      root.workflowNode = { id: "root", kind: "menu", label: dynamicSearchExtension.label,
        description: dynamicSearchExtension.description, items: dynamicSearchEntry.items }
      if (dynamicSearchEntry.node.submenuCommand && dynamicSearchEntry.node.submenuCommand.length > 0)
        root.enterSubmenu(dynamicSearchEntry.node)
      else if (dynamicSearchEntry.node.documentCommand && dynamicSearchEntry.node.documentCommand.length > 0)
        root.enterDocument(dynamicSearchEntry.node)
      else if (dynamicSearchEntry.node.kind === "action") root.dispatchWorkflowNode(dynamicSearchEntry.node, "")
      else if (dynamicSearchEntry.node.kind === "confirm") {
        root.workflowConfirmNode = dynamicSearchEntry.node
        root.workflowConfirmOpen = true
        root.rebuildDisplay()
      } else root.showWorkflowNode(dynamicSearchEntry.node, root.workflowContext, true)
      return
    }
    var rootExtension = root.extensionForRootId(row.itemId)
    if (rootExtension) {
      if (rootExtension.available && rootExtension.mode !== "menu") usage.record(row.itemId)
      root.activateExtensionRoot(rootExtension)
      return
    }
    if (root.actionPanelActive && row.itemId.indexOf("file.action.") === 0) {
      root.activateFileAction(row.action)
      return
    }
    if (row.itemId.indexOf("dependency.setup.") === 0) {
      var setupExtension = root.extensionById(row.itemId.substring("dependency.setup.".length))
      root.dependencyTarget = MenuModel.dependencySetup(setupExtension)
      root.dependencyConfirmOpen = root.dependencyTarget !== null
      return
    }
    if (row.itemId.indexOf("extension.unavailable.") === 0) {
      var unavailableExtension = root.extensionById(row.itemId.substring("extension.unavailable.".length))
      var setup = MenuModel.dependencySetup(unavailableExtension)
      if (setup) {
        root.dependencyTarget = setup
        root.dependencyConfirmOpen = true
      }
      return
    }
    if (row.itemId === "extension.result.pending") return
    if (row.itemId.indexOf("extension.prepare.") === 0) {
      var preparedExtension = root.extensionById(row.itemId.substring("extension.prepare.".length))
      if (preparedExtension && preparedExtension.mode === "files") root.enterFileBrowser(preparedExtension)
      else if (preparedExtension && preparedExtension.mode === "workflow") root.enterWorkflow(preparedExtension)
      else root.setFilter(row.action)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      return
    }
    var favorite = MenuModel.fileFavorite(row.itemId)
    if (favorite) {
      var filesExtension = root.filesExtensionForCapability(favorite.capability)
      if (!filesExtension || !filesExtension.available) return
      if (favorite.type === "directory") {
        root.enterFileBrowser(filesExtension, favorite.path)
      } else {
        var favoriteOpenCommand = root.shellCommand(filesExtension.command, { path: favorite.path })
        root.applySerial = root.requestSerial
        root.opened = false
        root.runAction(favoriteOpenCommand)
      }
      return
    }
    if (row.itemId.indexOf("extension.workflow.") === 0) {
      root.enterWorkflow(root.extensionById(row.itemId.substring("extension.workflow.".length)))
      return
    }
    if (root.workflowActive && !root.fileBrowserActive && row.itemId.indexOf("workflow.node.") === 0) {
      root.activateWorkflowChild(Number(row.action))
      return
    }
    if (root.directoryPickerActive && row.itemId === "workflow.directory.select") {
      root.selectWorkflowDirectory(row.action)
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
        root.resetFileIndex()
        root.applySerial = root.requestSerial
        root.opened = false
        root.runAction(openCommand)
      }
      return
    }
    if (root.isFontSizeSetting(row.itemId)) {
      root.setMenuItemFontClass(row.action)
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

  function cancelDependencyInstall() {
    root.dependencyConfirmOpen = false
    root.dependencyTarget = null
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDependencyInstall() {
    var setup = root.dependencyTarget
    root.dependencyConfirmOpen = false
    root.dependencyTarget = null
    if (!setup) return

    // Close the exclusive-focus launcher before opening the visible terminal.
    // --hold preserves package-manager output after success, failure, or
    // cancellation. Reopening Omalaunch performs a fresh extension check.
    root.opened = false
    root.runAction(root.shellCommand(
      ["xdg-terminal-exec", "--hold", "--"].concat(setup.installCommand),
      {}
    ))
  }

  function toggleSelectedStar() {
    if (root.dmenuActive || !root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.itemId === "omarchy" || row.itemId === "extensions"
        || row.itemId === "extension.result" || row.itemId === "extension.result.pending" || !favorites.loaded) return
    if (root.fileBrowserActive) {
      var fileType = row.itemId.indexOf("file.directory.") === 0 ? "directory"
        : (row.itemId.indexOf("file.item.") === 0 ? "file" : "")
      if (!fileType) return
      root.pendingStarSelectionId = row.itemId
      root.toggleFileFavorite(row.action, fileType)
      return
    }
    var favorite = MenuModel.fileFavorite(row.itemId)
    root.pendingStarSelectionId = row.itemId
    if (favorite) root.unstarFileFavorite(favorite)
    else favorites.toggle(row.itemId)
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

  function resetForOpen() {
    if (root.dmenuActive && root.requestActive) root.finishRequest(null)
    root.invalidateWorkflowAction("new launcher session")
    root.invalidateSubmenu("new launcher session")
    root.invalidateDocument("new launcher session")
    root.invalidateDynamicMenu()
    root.routePendingForMenuSources = false
    root.resetFileIndex()
    root.fileBrowserShowHidden = false
    root.invalidateExtensionQuery("new launcher session")

    var reset = MenuModel.openStateReset()
    for (var key in reset) root[key] = reset[key]
    root.mode = "menu"
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""
    root.dmenuPrompt = ""
    root.dmenuOptions = []
    root.dmenuRows = []
    root.navStack = []
    root.filterText = ""
    root.opened = false
  }

  function cancel() {
    root.invalidateWorkflowAction("launcher canceled")
    root.invalidateSubmenu("launcher canceled")
    root.invalidateDocument("launcher canceled")
    root.invalidateDynamicMenu()
    root.workflowConfirmOpen = false
    root.workflowConfirmNode = null
    root.routePendingForMenuSources = false
    if (root.dmenuActive) root.finishRequest(null)
    root.resetFileIndex()
    root.actionPanelActive = false
    root.actionPanelFile = null
    root.fileBrowserActive = false
    root.directoryPickerActive = false
    root.fileBrowserExtension = null
    root.workflowActive = false
    root.workflowExtension = null
    root.workflowNode = null
    root.workflowContext = ({})
    root.workflowStack = []
    root.dynamicMenuLoading = false
    root.focusedExtension = null
    root.extensionQuery = ""
    root.extensionResult = ""
    root.resultExtension = null
    root.unavailableResultExtension = null
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
    focusedExtension = null
    filterText = ""
    selectedIndex = 0
    cursorActive = true
    root.disarmPointer()
    root.evaluateGuards(false)
    opened = true
    rebuildDisplay()
    invalidateVolatileProvider(activeMenu)
    loadProviderForMenu(activeMenu)
    if (activeMenu === "root") root.loadProviderForMenu("apps")
    // The shell may start before first-install packages have finished placing
    // their icons. Keep the open-time fallback, but avoid rescanning every icon
    // directory on each rapid launcher invocation.
    root.refreshAppIconsIfStale()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openDmenu(payload) {
    root.routePendingForMenuSources = false
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    // Normalize caller rows once rather than splitting and lowercasing every
    // option again on each keystroke.
    dmenuRows = []
    for (var i = 0; i < dmenuOptions.length; i++) {
      var parts = String(dmenuOptions[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      dmenuRows.push({
        index: i,
        icon: icon,
        label: label,
        detail: detail,
        searchText: (label + "\n" + detail).toLowerCase()
      })
    }
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
    if (!root.rowsLoaded || !root.defaultMenuSettled || !root.userMenuSettled
        || menuSourceRebuildCoalescer.running) {
      // Resolve aliases and actions only after both menu snapshots have been
      // merged. The latest summon wins if several arrive during a reload.
      root.pendingInitialMenu = initialMenu
      root.routePendingForMenuSources = true
      return "ok"
    }
    root.routePendingForMenuSources = false
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
      if (exitCode === 0) {
        root.cancel()
        return
      }
      root.fileCopyFeedbackPath = fileCopyProc.copyPath
      root.fileCopyFeedback = "Copy failed"
      if (root.fileBrowserActive) root.rebuildFileDisplay()
      fileCopyFeedbackTimer.restart()
    }
  }

  Process {
    id: pasteProc
    command: ["wl-paste", "--no-newline", "--type", "text"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.workflowInputActive) return
        var limit = root.workflowNode ? root.workflowNode.maxLength : 4096
        root.setFilter((root.filterText + text).substring(0, limit))
      }
    }
  }

  Timer {
    id: fileScanTimer
    interval: 120
    repeat: false
    onTriggered: {
      if (!root.fileBrowserActive || !root.fileBrowserPath || fileScanProc.stopping) return
      var base = root.fileBrowserPath
      var needle = root.filterText.trim()

      if (needle) {
        var stale = root.fileIndexBuiltAt > 0
          && Date.now() - root.fileIndexBuiltAt >= root.fileIndexTtlMs
        if (root.fileIndexRoot !== base || !root.fileIndexReady || stale) {
          root.startFileIndex(base)
          return
        }
      }

      fileScanProc.revision = root.fileScanSerial
      fileScanProc.scanPath = base
      fileScanProc.query = needle
      fileScanProc.collected = ""
      fileScanProc.outputOverflow = false
      fileScanProc.command = needle
        ? ["python", root.fileIndexHelper, "query", root.fileIndexPath, needle]
        : ["python", root.fileIndexHelper, root.directoryPickerActive ? "browse-dirs" : "browse"]
          .concat(root.fileScanOptions()).concat(["--", base])
      fileScanProc.running = true
    }
  }

  Process {
    id: fileIndexProc
    property int revision: 0
    property string indexRoot: ""
    property string indexPath: ""
    property bool stopping: false
    onExited: function(exitCode) {
      var stale = fileIndexProc.stopping
        || fileIndexProc.revision !== root.fileIndexSerial
        || fileIndexProc.indexRoot !== root.fileBrowserPath
      fileIndexProc.stopping = false
      if (stale) {
        root.removeFileIndex(fileIndexProc.indexPath)
        if (root.fileBrowserActive && root.filterText.trim())
          Qt.callLater(function() { root.scheduleFileScan(true) })
        return
      }
      root.fileIndexReady = exitCode === 0
      root.fileIndexBuiltAt = root.fileIndexReady ? Date.now() : 0
      if (!root.fileIndexReady) {
        root.removeFileIndex(fileIndexProc.indexPath)
        if (root.fileIndexPath === fileIndexProc.indexPath) root.fileIndexPath = ""
      }
      if (root.fileIndexReady && root.fileBrowserActive && root.filterText.trim())
        Qt.callLater(function() { root.scheduleFileScan(true) })
    }
  }

  Process {
    id: fileScanProc
    property int revision: 0
    property string scanPath: ""
    property string query: ""
    property string collected: ""
    property bool outputOverflow: false
    property bool stopping: false
    stdout: SplitParser { onRead: function(data) { root.collectBounded(fileScanProc, data) } }
    onExited: function(exitCode) {
      var stale = fileScanProc.stopping
        || fileScanProc.revision !== root.fileScanSerial
        || !root.fileBrowserActive
        || fileScanProc.scanPath !== root.fileBrowserPath
        || fileScanProc.query !== root.filterText.trim()
      fileScanProc.stopping = false
      if (stale) {
        if (root.fileBrowserActive)
          Qt.callLater(function() { root.scheduleFileScan(true) })
        return
      }
      var entries = []
      if (exitCode === 0 && !fileScanProc.outputOverflow) {
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
      var revision = root.extensionQuerySerial
      var query = root.effectiveExtensionQuery()
      var queryCatalog = root.focusedExtension ? [root.focusedExtension] : root.extensions
      var extension = MenuModel.queryExtension(queryCatalog, query)
      if (!extension || revision !== root.extensionQuerySerial) return
      root.resultExtension = extension
      root.queueExtensionQuery(extension, query, revision)
    }
  }

  Timer {
    id: extensionQueryTimeout
    interval: root.extensionQueryTimeoutMs
    repeat: false
    property int generation: 0
    onTriggered: {
      if (generation !== extensionQueryProc.generation || extensionQueryProc.stopping) return
      console.warn("Omalaunch: live query timed out after " + interval + "ms")
      root.stopExtensionQuery("query timed out")
    }
  }

  Timer {
    id: extensionQueryKillTimer
    interval: root.extensionQueryTerminationGraceMs
    repeat: false
    property int generation: 0
    onTriggered: {
      if (!extensionQueryProc.stopping || generation !== extensionQueryProc.stopGeneration
          || generation !== extensionQueryProc.generation) return
      console.warn("Omalaunch: live query ignored SIGTERM; sending SIGKILL to direct child")
      extensionQueryProc.signal(9)
    }
  }

  Process {
    id: extensionQueryProc
    property string query: ""
    property string extensionId: ""
    property string collected: ""
    property bool outputOverflow: false
    property int revision: 0
    property int generation: 0
    property int stopGeneration: 0
    property bool stopping: false
    stdout: SplitParser {
      onRead: function(data) { root.collectExtensionQuery(data) }
    }
    onExited: function(exitCode) {
      var exitedGeneration = extensionQueryProc.generation
      var wasStopping = extensionQueryProc.stopping
      if (extensionQueryTimeout.generation === exitedGeneration) extensionQueryTimeout.stop()
      if (extensionQueryKillTimer.generation === exitedGeneration) extensionQueryKillTimer.stop()

      var accept = MenuModel.extensionQueryRunIsCurrent(
        extensionQueryProc.revision, root.extensionQuerySerial,
        extensionQueryProc.query, root.effectiveExtensionQuery(),
        extensionQueryProc.extensionId, root.resultExtension,
        wasStopping, root.opened
      )
      if (accept) {
        root.extensionQuery = extensionQueryProc.query
        root.extensionResult = exitCode === 0 && !extensionQueryProc.outputOverflow ? extensionQueryProc.collected.trim() : ""
        root.rebuildDisplay()
        if (root.extensionResult && root.resultExtension.capability === "currency") currencyRates.refreshIfStale()
      }

      // Only onExited makes this reusable. No request metadata or command is
      // changed before these flags are released, and rapid input has retained
      // exactly one latest request in pendingExtensionQuery.
      extensionQueryProc.stopping = false
      extensionQueryProc.stopGeneration = 0
      extensionQueryProc.generation = 0
      root.dispatchPendingExtensionQuery()
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
        : { extensions: [], diagnostics: [extensionProc.outputOverflow ? "Extension catalog exceeded the output limit" : "Extension loader exited with code " + exitCode], valid: false, complete: false }
      var haveKnownGood = root.extensionsLoadedAt > 0
      var acceptCatalog = catalog.valid && (catalog.complete || !haveKnownGood)
      if (acceptCatalog) {
        // Catalog changes invalidate commands and node objects captured by an
        // in-flight action before any refreshed state is installed.
        root.invalidateWorkflowAction("extension catalog changed")
        var focusedCapability = root.focusedExtension ? root.focusedExtension.capability : ""
        var focusedId = root.focusedExtension ? root.focusedExtension.id : ""
        var workflowCapability = root.workflowExtension ? root.workflowExtension.capability : ""
        var workflowId = root.workflowExtension ? root.workflowExtension.id : ""
        var fileCapability = root.fileBrowserExtension ? root.fileBrowserExtension.capability : ""
        var fileId = root.fileBrowserExtension ? root.fileBrowserExtension.id : ""
        var oldWorkflowNode = root.workflowNode
        var oldWorkflowStack = root.workflowStack
        root.extensions = catalog.extensions
        root.menuItemFontClass = catalog.omalaunchConfig && catalog.omalaunchConfig.menuItemFontClass
          ? catalog.omalaunchConfig.menuItemFontClass : "title"
        root.configuredMenuItemFontSize = catalog.omalaunchConfig && catalog.omalaunchConfig.menuItemFontSize !== undefined
          ? catalog.omalaunchConfig.menuItemFontSize : 0
        favorites.configure(catalog.providerConfig, catalog.migrationComplete)
        root.preloadDynamicMenuSearch()

        if (focusedCapability) {
          var refreshedFocus = root.extensionByCapability(focusedCapability) || root.extensionById(focusedId)
          if (refreshedFocus && refreshedFocus.available
              && (refreshedFocus.mode === "prefix" || refreshedFocus.mode === "query")) root.focusedExtension = refreshedFocus
          else root.leaveFocusedExtension()
        }
        if (root.workflowActive) {
          var refreshedWorkflow = root.extensionByCapability(workflowCapability) || root.extensionById(workflowId)
          if (refreshedWorkflow && refreshedWorkflow.available && refreshedWorkflow.mode === "menu") {
            root.leaveWorkflow()
            root.enterDynamicMenu(refreshedWorkflow)
          } else {
            var rebound = MenuModel.rebindWorkflow(refreshedWorkflow, oldWorkflowStack, oldWorkflowNode)
            if (rebound) {
              root.workflowExtension = refreshedWorkflow
              root.workflowNode = rebound.node
              root.workflowStack = rebound.stack
            } else root.leaveWorkflow()
          }
        }
        if (root.fileBrowserActive) {
          var refreshedFiles = root.filesExtensionForCapability(fileCapability) || root.extensionById(fileId)
          if (refreshedFiles && refreshedFiles.available && refreshedFiles.mode === "files") root.fileBrowserExtension = refreshedFiles
          else if (root.directoryPickerActive && root.workflowActive) root.workflowBack()
          else root.leaveFileBrowser(false)
        }
        if (catalog.complete) root.extensionsLoadedAt = Date.now()
      } else {
        catalog.diagnostics.unshift("Retained the last known-good extension catalog after a transient loader failure")
      }
      root.extensionDiagnostics = catalog.diagnostics
      for (var i = 0; i < catalog.diagnostics.length; i++) console.warn("Omalaunch: " + catalog.diagnostics[i])
      if (root.opened && !root.dmenuActive) {
        root.scheduleExtensionQuery()
        root.rebuildDisplay()
      }
      if (root.extensionsReloadPending) root.loadExtensions(true)
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

  Timer {
    id: dynamicMenuSearchProviderTimeout
    interval: root.dynamicMenuTimeoutMs
    repeat: false
    property int generation: 0
    onTriggered: if (generation === root.dynamicMenuSearchGeneration)
      root.rejectDynamicMenuSearch("global menu search provider timed out after " + interval + "ms")
  }

  Timer {
    id: dynamicMenuSearchTotalTimeout
    interval: root.dynamicMenuSearchTotalTimeoutMs
    repeat: false
    property int generation: 0
    onTriggered: if (generation === root.dynamicMenuSearchGeneration)
      root.rejectDynamicMenuSearch("global menu search preload exceeded the aggregate time limit")
  }

  Timer {
    id: dynamicMenuSearchKillTimer
    interval: root.dynamicMenuTerminationGraceMs
    repeat: false
    property int generation: 0
    onTriggered: {
      if (!dynamicMenuSearchProc.stopping || generation !== dynamicMenuSearchProc.stopGeneration
          || generation !== dynamicMenuSearchProc.generation) return
      console.warn("Omalaunch: global menu search provider ignored SIGTERM; sending SIGKILL to direct child")
      dynamicMenuSearchProc.signal(9)
    }
  }

  Process {
    id: dynamicMenuSearchProc
    property int generation: 0
    property int stopGeneration: 0
    property var extension: null
    property bool stopping: false
    property string collected: ""
    property int stderrBytes: 0
    property bool outputOverflow: false
    stdout: SplitParser {
      onRead: function(data) {
        if (dynamicMenuSearchProc.outputOverflow) return
        var nextBytes = root.dynamicMenuSearchOutputBytes + data.length + 1
        var next = dynamicMenuSearchProc.collected + data + "\n"
        if (next.length > root.dynamicMenuOutputBytes || nextBytes > root.dynamicMenuSearchMaxOutputBytes) {
          dynamicMenuSearchProc.outputOverflow = true
          root.rejectDynamicMenuSearch("global menu search provider exceeded an output limit")
        } else {
          root.dynamicMenuSearchOutputBytes = nextBytes
          dynamicMenuSearchProc.collected = next
        }
      }
    }
    stderr: SplitParser {
      onRead: function(data) {
        if (dynamicMenuSearchProc.outputOverflow) return
        dynamicMenuSearchProc.stderrBytes += data.length + 1
        root.dynamicMenuSearchOutputBytes += data.length + 1
        if (dynamicMenuSearchProc.stderrBytes > root.dynamicMenuOutputBytes
            || root.dynamicMenuSearchOutputBytes > root.dynamicMenuSearchMaxOutputBytes) {
          dynamicMenuSearchProc.outputOverflow = true
          root.rejectDynamicMenuSearch("global menu search provider exceeded an output limit")
        }
      }
    }
    onExited: function(exitCode) {
      dynamicMenuSearchProviderTimeout.stop()
      if (dynamicMenuSearchKillTimer.generation === dynamicMenuSearchProc.generation)
        dynamicMenuSearchKillTimer.stop()
      dynamicMenuSearchProc.stopGeneration = 0
      if (dynamicMenuSearchProc.generation !== root.dynamicMenuSearchGeneration) {
        dynamicMenuSearchProc.stopping = false
        root.startDynamicMenuSearchProvider()
        return
      }
      dynamicMenuSearchProc.stopping = false
      if (exitCode !== 0 || dynamicMenuSearchProc.outputOverflow) {
        root.rejectDynamicMenuSearch("global menu search provider failed or exceeded an output limit")
        return
      }
      var workflow = MenuModel.normalizeDynamicMenuOutput(dynamicMenuSearchProc.collected)
      if (!workflow) {
        root.rejectDynamicMenuSearch("global menu search provider returned an invalid snapshot")
        return
      }
      var searchItems = MenuModel.dynamicMenuSearchItems(dynamicMenuSearchProc.extension, workflow)
      if (root.dynamicMenuSearchCandidate.length + searchItems.length > root.dynamicMenuSearchMaxRows) {
        root.rejectDynamicMenuSearch("global menu search preload exceeds the aggregate row limit")
        return
      }
      var candidate = root.dynamicMenuSearchCandidate.slice()
      for (var i = 0; i < searchItems.length; i++) {
        var searchNode = null
        for (var nodeIndex = 0; nodeIndex < workflow.items.length; nodeIndex++)
          if (workflow.items[nodeIndex].id === searchItems[i].action) { searchNode = workflow.items[nodeIndex]; break }
        if (!searchNode) {
          root.rejectDynamicMenuSearch("global menu search row lost its normalized provider identity")
          return
        }
        candidate.push({
          item: searchItems[i], node: searchNode, items: workflow.items,
          capability: dynamicMenuSearchProc.extension.capability, extensionId: dynamicMenuSearchProc.extension.id
        })
      }
      root.dynamicMenuSearchCandidate = candidate
      if (root.dynamicMenuSearchQueue.length > 0) root.startDynamicMenuSearchProvider()
      else {
        dynamicMenuSearchTotalTimeout.stop()
        root.dynamicMenuSearchSnapshot = candidate
        root.dynamicMenuSearchCandidate = []
        root.rebuildDisplay()
      }
    }
  }

  Timer {
    id: submenuTimeout
    interval: root.submenuTimeoutMs
    repeat: false
    onTriggered: {
      if (!submenuProc.running) return
      console.warn("Omalaunch: submenu provider timed out after " + interval + "ms")
      root.invalidateSubmenu("submenu provider timed out")
      if (root.workflowNode) root.workflowNode = Object.assign({}, root.workflowNode,
        { description: "Provider timed out", items: [] })
      root.rebuildDisplay()
    }
  }

  Timer {
    id: submenuKillTimer
    interval: root.submenuTerminationGraceMs
    repeat: false
    property int generation: 0
    onTriggered: {
      if (!submenuProc.stopping || generation !== submenuProc.stopGeneration
          || generation !== submenuProc.generation) return
      console.warn("Omalaunch: submenu provider ignored SIGTERM; sending SIGKILL to direct child")
      submenuProc.signal(9)
    }
  }

  Process {
    id: submenuProc
    property int generation: 0
    property int stopGeneration: 0
    property bool stopping: false
    property string extensionCapability: ""
    property string submenuNodeId: ""
    property string collected: ""
    property int stderrBytes: 0
    property bool outputOverflow: false
    stdout: SplitParser {
      onRead: function(data) {
        if (submenuProc.outputOverflow) return
        var next = submenuProc.collected + data + "\n"
        if (next.length > root.submenuOutputBytes) {
          submenuProc.outputOverflow = true
          submenuProc.collected = ""
          root.invalidateSubmenu("submenu output exceeded limit")
          if (root.workflowNode) root.workflowNode = Object.assign({}, root.workflowNode,
            { description: "Provider output was too large", items: [] })
          root.rebuildDisplay()
        } else submenuProc.collected = next
      }
    }
    stderr: SplitParser {
      onRead: function(data) {
        if (submenuProc.outputOverflow) return
        submenuProc.stderrBytes += data.length + 1
        if (submenuProc.stderrBytes > root.submenuOutputBytes) {
          submenuProc.outputOverflow = true
          root.invalidateSubmenu("submenu error output exceeded limit")
          if (root.workflowNode) root.workflowNode = Object.assign({}, root.workflowNode,
            { description: "Provider error output was too large", items: [] })
          root.rebuildDisplay()
        }
      }
    }
    onExited: function(exitCode) {
      submenuTimeout.stop()
      submenuKillTimer.stop()
      submenuProc.stopGeneration = 0
      submenuProc.stopping = false
      if (submenuProc.generation !== root.submenuGeneration || !root.workflowActive
          || !root.workflowExtension
          || root.workflowExtension.capability !== submenuProc.extensionCapability
          || !root.workflowNode || root.workflowNode.id !== submenuProc.submenuNodeId) return
      root.submenuLoading = false
      var workflow = exitCode === 0 && !submenuProc.outputOverflow
        ? MenuModel.normalizeDynamicMenuOutput(submenuProc.collected) : null
      if (!workflow) {
        console.warn("Omalaunch: submenu provider returned invalid or failed output")
        root.workflowNode = Object.assign({}, root.workflowNode,
          { description: "Provider failed", items: [] })
      } else root.workflowNode = Object.assign({}, root.workflowNode,
        { description: "", items: workflow.items })
      root.selectedIndex = 0
      root.cursorActive = workflow && workflow.items.length > 0
      root.rebuildDisplay()
    }
  }

  Timer {
    id: documentTimeout
    interval: root.documentTimeoutMs
    repeat: false
    onTriggered: {
      if (!documentProc.running) return
      root.documentError = "Detail provider timed out"
      root.invalidateDocument("detail provider timed out")
      root.rebuildDisplay()
    }
  }

  Timer {
    id: documentKillTimer
    interval: root.documentTerminationGraceMs
    repeat: false
    property int generation: 0
    onTriggered: {
      if (!documentProc.stopping || generation !== documentProc.stopGeneration
          || generation !== documentProc.generation) return
      console.warn("Omalaunch: detail provider ignored SIGTERM; sending SIGKILL to direct child")
      documentProc.signal(9)
    }
  }

  Process {
    id: documentProc
    property int generation: 0
    property int stopGeneration: 0
    property bool stopping: false
    property string extensionCapability: ""
    property string documentNodeId: ""
    property string collected: ""
    property int stderrBytes: 0
    property bool outputOverflow: false
    stdout: SplitParser {
      onRead: function(data) {
        if (documentProc.outputOverflow) return
        var next = documentProc.collected + data + "\n"
        if (next.length > root.documentOutputBytes) {
          documentProc.outputOverflow = true
          documentProc.collected = ""
          root.documentError = "Detail provider output was too large"
          root.invalidateDocument("detail output exceeded limit")
          root.rebuildDisplay()
        } else documentProc.collected = next
      }
    }
    stderr: SplitParser {
      onRead: function(data) {
        if (documentProc.outputOverflow) return
        documentProc.stderrBytes += data.length + 1
        if (documentProc.stderrBytes > root.documentOutputBytes) {
          documentProc.outputOverflow = true
          root.documentError = "Detail provider error output was too large"
          root.invalidateDocument("detail error output exceeded limit")
          root.rebuildDisplay()
        }
      }
    }
    onExited: function(exitCode) {
      documentTimeout.stop()
      documentKillTimer.stop()
      documentProc.stopGeneration = 0
      documentProc.stopping = false
      if (documentProc.generation !== root.documentGeneration || !root.documentActive
          || !root.workflowExtension
          || root.workflowExtension.capability !== documentProc.extensionCapability
          || root.workflowNode.id !== documentProc.documentNodeId) return
      root.documentLoading = false
      var document = exitCode === 0 && !documentProc.outputOverflow
        ? MenuModel.normalizeDetailDocument(documentProc.collected) : null
      if (!document) {
        root.documentError = "Could not load details"
        console.warn("Omalaunch: detail provider returned invalid or failed output")
      } else {
        root.documentError = ""
        root.workflowNode = Object.assign({}, root.workflowNode, { document: document })
      }
      root.rebuildDisplay()
    }
  }

  Timer {
    id: dynamicMenuTimeout
    interval: root.dynamicMenuTimeoutMs
    repeat: false
    onTriggered: {
      if (!dynamicMenuProc.running) return
      console.warn("Omalaunch: dynamic menu provider timed out after " + interval + "ms")
      root.invalidateDynamicMenu()
    }
  }

  Timer {
    id: dynamicMenuKillTimer
    interval: root.dynamicMenuTerminationGraceMs
    repeat: false
    property int generation: 0
    onTriggered: {
      if (!dynamicMenuProc.stopping || generation !== dynamicMenuProc.stopGeneration
          || generation !== dynamicMenuProc.generation) return
      console.warn("Omalaunch: dynamic menu provider ignored SIGTERM; sending SIGKILL to direct child")
      dynamicMenuProc.signal(9)
    }
  }

  Process {
    id: dynamicMenuProc
    property int generation: 0
    property int stopGeneration: 0
    property bool stopping: false
    property string extensionCapability: ""
    property string selectionNodeId: ""
    property string collected: ""
    property bool outputOverflow: false
    stdout: SplitParser {
      onRead: function(data) {
        if (dynamicMenuProc.outputOverflow) return
        var next = dynamicMenuProc.collected + data + "\n"
        if (next.length > root.dynamicMenuOutputBytes) {
          dynamicMenuProc.outputOverflow = true
          dynamicMenuProc.collected = ""
          root.invalidateDynamicMenu()
        } else dynamicMenuProc.collected = next
      }
    }
    stderr: SplitParser {
      onRead: function(data) {
        if (dynamicMenuProc.outputOverflow) return
        dynamicMenuProc.stderrBytes += data.length + 1
        if (dynamicMenuProc.stderrBytes > root.dynamicMenuOutputBytes) {
          dynamicMenuProc.outputOverflow = true
          root.invalidateDynamicMenu()
        }
      }
    }
    property int stderrBytes: 0
    onExited: function(exitCode) {
      dynamicMenuTimeout.stop()
      dynamicMenuKillTimer.stop()
      dynamicMenuProc.stopGeneration = 0
      dynamicMenuProc.stopping = false
      if (dynamicMenuProc.generation !== root.dynamicMenuGeneration || !root.workflowActive
          || !root.workflowExtension || root.workflowExtension.mode !== "menu"
          || root.workflowExtension.capability !== dynamicMenuProc.extensionCapability) return
      root.dynamicMenuLoading = false
      var workflow = exitCode === 0 && !dynamicMenuProc.outputOverflow
        ? MenuModel.normalizeDynamicMenuOutput(dynamicMenuProc.collected) : null
      if (!workflow) {
        console.warn("Omalaunch: dynamic menu provider returned invalid or failed output")
        root.workflowNode = { id: "root", kind: "menu", label: root.workflowExtension.label,
          description: "Provider failed", items: [] }
      } else root.workflowNode = { id: "root", kind: "menu", label: root.workflowExtension.label,
        description: root.workflowExtension.description, items: workflow.items }
      var selectedWorkflowNodeIndex = -1
      if (workflow && dynamicMenuProc.selectionNodeId) {
        for (var selectedWorkflowIndex = 0; selectedWorkflowIndex < workflow.items.length; selectedWorkflowIndex++)
          if (workflow.items[selectedWorkflowIndex].id === dynamicMenuProc.selectionNodeId) { selectedWorkflowNodeIndex = selectedWorkflowIndex; break }
      }
      dynamicMenuProc.selectionNodeId = ""
      root.selectedIndex = 0
      root.cursorActive = workflow && workflow.items.length > 0
      root.rebuildDisplay()
      if (selectedWorkflowNodeIndex >= 0) {
        for (var selectedDisplayIndex = 0; selectedDisplayIndex < displayModel.count; selectedDisplayIndex++)
          if (Number(displayModel.get(selectedDisplayIndex).action) === selectedWorkflowNodeIndex) { root.selectedIndex = selectedDisplayIndex; break }
      }
    }
  }

  Timer {
    id: workflowActionTimeout
    interval: root.workflowActionTimeoutMs
    repeat: false
    onTriggered: {
      console.warn("Omalaunch: workflow action timed out after " + interval + "ms")
      root.invalidateWorkflowAction("workflow action timed out")
    }
  }

  Timer {
    id: workflowActionKillTimer
    interval: root.workflowTerminationGraceMs
    repeat: false
    property int generation: 0
    onTriggered: {
      if (!workflowActionProc.stopping || generation !== workflowActionProc.stopGeneration) return
      console.warn("Omalaunch: workflow action ignored SIGTERM; sending SIGKILL to direct child")
      workflowActionProc.signal(9)
    }
  }

  Process {
    id: workflowActionProc
    property int generation: 0
    property int stopGeneration: 0
    property bool stopping: false
    property string extensionCapability: ""
    property var nextNode: null
    property var nextContext: ({})
    property bool refreshExtensions: false
    property bool refreshDynamicMenu: false
    property int nextBackSteps: 0
    property bool closeAfter: false
    property bool returnToRoot: false
    property string usageItemId: ""
    onExited: function(exitCode) {
      console.warn("Omalaunch action exit: " + exitCode + " command=" + JSON.stringify(workflowActionProc.command))
      workflowActionTimeout.stop()
      workflowActionKillTimer.stop()
      workflowActionProc.stopGeneration = 0
      workflowActionProc.stopping = false
      if (!MenuModel.workflowActionIsCurrent(workflowActionProc.generation, root.workflowGeneration,
          root.workflowActive, workflowActionProc.extensionCapability, root.workflowExtension)) return
      workflowActionProc.generation = 0
      if (exitCode !== 0) { workflowActionProc.returnToRoot = false; workflowActionProc.usageItemId = ""; return }
      var usageItemId = workflowActionProc.usageItemId
      workflowActionProc.usageItemId = ""
      if (usageItemId) usage.record(usageItemId)
      if (workflowActionProc.returnToRoot) {
        workflowActionProc.returnToRoot = false
        root.workflowActive = false
        root.workflowExtension = null
        root.workflowNode = null
        root.workflowContext = ({})
        root.workflowStack = []
        root.filterText = ""
        root.preloadDynamicMenuSearch()
        root.rebuildDisplay()
        return
      }
      if (root.workflowExtension.mode === "menu") root.preloadDynamicMenuSearch()
      if (workflowActionProc.refreshExtensions) root.loadExtensions(true)
      if (workflowActionProc.refreshDynamicMenu) {
        var extension = root.workflowExtension
        root.enterDynamicMenu(extension, true)
      } else if (workflowActionProc.closeAfter) {
        root.cancel()
      } else if (workflowActionProc.nextNode) {
        if (workflowActionProc.nextBackSteps > 0) {
          var removeCount = workflowActionProc.nextBackSteps - 1
          root.workflowStack = root.workflowStack.slice(0, Math.max(0, root.workflowStack.length - removeCount))
          root.showWorkflowNode(workflowActionProc.nextNode, workflowActionProc.nextContext, false)
        } else root.showWorkflowNode(workflowActionProc.nextNode, workflowActionProc.nextContext, true)
      }
    }
  }

  Timer {
    id: backgroundActionTimeout
    interval: root.backgroundActionTimeoutMs
    repeat: false
    onTriggered: {
      console.warn("Omalaunch: background action timed out: " + backgroundActionProc.actionId)
      root.invalidateBackgroundAction("background action timed out")
    }
  }

  Timer {
    id: backgroundActionKillTimer
    interval: root.workflowTerminationGraceMs
    repeat: false
    property int generation: 0
    onTriggered: {
      if (!backgroundActionProc.stopping || generation !== backgroundActionProc.stopGeneration) return
      console.warn("Omalaunch: background action ignored SIGTERM; sending SIGKILL to direct child")
      backgroundActionProc.signal(9)
    }
  }

  Process {
    id: backgroundActionProc
    property int generation: 0
    property int stopGeneration: 0
    property bool stopping: false
    property string extensionCapability: ""
    property string actionId: ""
    property bool refreshExtensions: false
    property bool closeAfter: false
    property string usageItemId: ""
    onExited: function(exitCode) {
      backgroundActionTimeout.stop()
      backgroundActionKillTimer.stop()
      backgroundActionProc.stopGeneration = 0
      backgroundActionProc.stopping = false
      var extension = root.extensionByCapability(backgroundActionProc.extensionCapability)
      if (!MenuModel.backgroundActionIsCurrent(backgroundActionProc.generation,
          root.backgroundActionGeneration, backgroundActionProc.extensionCapability, extension)) return
      backgroundActionProc.generation = 0
      if (exitCode !== 0) {
        backgroundActionProc.usageItemId = ""
        console.warn("Omalaunch: background action failed (exit " + exitCode + "): " + backgroundActionProc.actionId)
        return
      }
      var usageItemId = backgroundActionProc.usageItemId
      backgroundActionProc.usageItemId = ""
      if (usageItemId) usage.record(usageItemId)
      if (backgroundActionProc.refreshExtensions) root.loadExtensions(true)
      root.preloadDynamicMenuSearch()
      if (root.workflowActive && root.workflowExtension
          && root.workflowExtension.capability === extension.capability)
        root.enterDynamicMenu(extension, true)
      if (backgroundActionProc.closeAfter) root.cancel()
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

  // Desktop-entry and hidden-filter watchers can emit appsChanged several
  // times in one burst. Each merge sorts every app, rebuilds derived search
  // metadata, and may rebuild the visible ListModel, so coalesce the burst.
  Timer {
    id: appRowsMergeDebounce
    interval: 100
    repeat: false
    onTriggered: if (root.providersLoaded["apps"]) root.mergeAppRows()
  }

  Connections {
    target: root.appLibrary
    function onIconIndexChanged() {
      // iconIndex is swapped only when AppLibrary's asynchronous scan exits.
      // Start the freshness window from completion, not from the request.
      root.appIconIndexUpdatedAt = Date.now()
      root.appIconRefreshPending = false
    }
    function onAppsChanged() {
      // AppLibrary owns app-change icon rescans; this signal can also mean only
      // hidden filters changed, so it must not advance the freshness window.
      // Bound staleness to one interval from the first signal. Later signals
      // in the same window are already represented by the eventual snapshot.
      if (root.providersLoaded["apps"] && !appRowsMergeDebounce.running)
        appRowsMergeDebounce.start()
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
  // The default and user FileViews settle independently at startup and during
  // refreshes. A full rebuild resets providers and forces an expensive guard
  // batch, so wait for both initial snapshots and coalesce later change bursts
  // into one bounded rebuild window.
  function scheduleMenuSourceRebuild() {
    if (!root.defaultMenuSettled || !root.userMenuSettled) return
    if (!menuSourceRebuildCoalescer.running) menuSourceRebuildCoalescer.start()
  }

  function requestDefaultMenuReload() {
    root.defaultMenuSettled = false
    if (root.defaultMenuLoading) {
      root.defaultMenuReloadPending = true
      return
    }
    root.defaultMenuLoading = true
    defaultMenuFile.reload()
  }

  function requestUserMenuReload() {
    root.userMenuSettled = false
    if (root.userMenuLoading) {
      root.userMenuReloadPending = true
      return
    }
    root.userMenuLoading = true
    userMenuFile.reload()
  }

  function finishDefaultMenuReload() {
    if (root.defaultMenuReloadPending) {
      root.defaultMenuReloadPending = false
      // Leave loading set while callLater moves beyond FileView's completion
      // signal; reload() during that signal can still target the old read.
      Qt.callLater(function() { defaultMenuFile.reload() })
      return
    }
    root.defaultMenuLoading = false
    root.defaultMenuSettled = true
    root.scheduleMenuSourceRebuild()
  }

  function finishUserMenuReload() {
    if (root.userMenuReloadPending) {
      root.userMenuReloadPending = false
      Qt.callLater(function() { userMenuFile.reload() })
      return
    }
    root.userMenuLoading = false
    root.userMenuSettled = true
    root.scheduleMenuSourceRebuild()
  }

  Timer {
    id: menuSourceRebuildCoalescer
    interval: 50
    repeat: false
    onTriggered: {
      // A reload may start while this fixed window is running. Its completion
      // schedules the next window, so never rebuild from an in-flight snapshot.
      if (root.defaultMenuSettled && root.userMenuSettled)
        root.rebuildItemsFromSources()
    }
  }

  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      var snapshot = root.parseMenuJsoncSnapshot(text())
      // A truncate-and-write save can expose partial JSON through a successful
      // read. Keep the last valid snapshot until a complete document arrives.
      if (snapshot.valid) root.defaultMenuItems = snapshot.items
      root.finishDefaultMenuReload()
    }
    onLoadFailed: {
      // Keep the last valid default snapshot across transient reload failures.
      root.finishDefaultMenuReload()
    }
    onFileChanged: root.requestDefaultMenuReload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      var snapshot = root.parseMenuJsoncSnapshot(text())
      if (snapshot.valid) root.userMenuItems = snapshot.items
      root.finishUserMenuReload()
    }
    onLoadFailed: {
      root.userMenuItems = []
      root.finishUserMenuReload()
    }
    onFileChanged: root.requestUserMenuReload()
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
  property bool guardsForcePending: false
  property double guardsEvaluatedAt: 0
  readonly property int guardRefreshTtlMs: 10 * 1000

  function evaluateGuards(force) {
    var forced = force === true
    if (!forced && root.guardsEvaluatedAt > 0
        && Date.now() - root.guardsEvaluatedAt < root.guardRefreshTtlMs) return
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      root.guardsPending = true
      if (forced) root.guardsForcePending = true
      return
    }
    root.guardsPending = false
    root.guardsForcePending = false

    var script = MenuModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      root.rebuildItemMetadata()
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: settingsProc
    property string pendingFontClass: ""
    property string queuedFontClass: ""
    onExited: function(exitCode) {
      if (exitCode === 0 && pendingFontClass) {
        root.menuItemFontClass = pendingFontClass
        root.configuredMenuItemFontSize = 0
        root.settingsFeedback = ""
        root.rebuildDisplay()
        root.loadExtensions(true)
      } else root.settingsFeedback = "Could not save font size"
      pendingFontClass = ""
      if (queuedFontClass) {
        var nextFontClass = queuedFontClass
        queuedFontClass = ""
        Qt.callLater(function() { root.setMenuItemFontClass(nextFontClass) })
      }
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
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
        if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards(root.guardsForcePending) })
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
      root.rebuildItemMetadata()
      root.guardsEvaluatedAt = Date.now()
      if (root.opened) root.rebuildDisplay()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
      if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards(root.guardsForcePending) })
    }
  }
  Component.onDestruction: root.resetFileIndex()

  PanelWindow {
    id: panel
    visible: root.opened && root.rowsLoaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // Keep the top edge fixed while result and submenu heights change.
    readonly property int pinnedTop: Math.max(Style.gapsOut, Math.round(height * 0.25))

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
      height: Math.min(root.cardHeight, panel.height - Style.gapsOut - panel.pinnedTop)
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      y: panel.pinnedTop
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: (root.workflowConfirmOpen || root.deleteConfirmOpen || root.dependencyConfirmOpen) ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.workflowConfirmOpen) {
            if (workflowConfirm.handleKey(event)) event.accepted = true
            return
          }
          if (root.deleteConfirmOpen) {
            if (deleteConfirm.handleKey(event)) event.accepted = true
            return
          }
          if (root.dependencyConfirmOpen) {
            if (dependencyConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (!root.dmenuActive && event.key === Qt.Key_Comma && (event.modifiers & Qt.ControlModifier)) {
            root.openSettings()
            event.accepted = true
          } else if (root.workflowInputActive
              && ((event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier))
                || (event.key === Qt.Key_Insert && (event.modifiers & Qt.ShiftModifier)))) {
            if (!pasteProc.running) pasteProc.running = true
            event.accepted = true
          } else if (!root.workflowActive && root.selectedDynamicSearchEntry && event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) {
            root.openDynamicSearchActions()
            event.accepted = true
          } else if (root.workflowActive && !root.fileBrowserActive && event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) {
            root.openWorkflowActions()
            event.accepted = true
          } else if (root.fileBrowserActive && !root.directoryPickerActive && !root.actionPanelActive && event.key === Qt.Key_H && (event.modifiers & Qt.ControlModifier)) {
            root.toggleHiddenFiles()
            event.accepted = true
          } else if (root.fileBrowserActive && !root.directoryPickerActive && !root.actionPanelActive && event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) {
            root.openActionPanel()
            event.accepted = true
          } else if (root.fileBrowserActive && !root.directoryPickerActive && !root.actionPanelActive && event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
            root.copySelectedFilePath()
            event.accepted = true
          } else if (root.workflowActive && root.selectedWorkflowStarAction && event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
            root.toggleSelectedWorkflowStar()
            event.accepted = true
          } else if (!root.workflowActive && root.selectedDynamicStarAction && event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
            root.toggleSelectedDynamicStar()
            event.accepted = true
          } else if (!root.dmenuActive && !root.workflowActive && event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
            root.toggleSelectedStar()
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            root.requestDeleteSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.actionPanelActive) root.closeActionPanel()
            else if (root.workflowInputActive) root.workflowBack()
            else if (root.focusedExtension) root.leaveFocusedExtension()
            else if (root.filterText) root.setFilter("")
            else if (root.directoryPickerActive) root.workflowBack()
            else if (root.fileBrowserActive) root.leaveFileBrowser()
            else if (root.workflowActive) root.workflowBack()
            else if (root.activeMenu !== "root") root.goBack()
            else root.cancel()
            event.accepted = true
          } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
              && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            root.select(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
            event.accepted = true
          } else if (root.documentActive && (event.key === Qt.Key_Up || event.key === Qt.Key_PageUp)) {
            documentFlick.contentY = Math.max(documentFlick.originY,
              documentFlick.contentY - (event.key === Qt.Key_PageUp ? documentFlick.height * 0.8 : Style.space(48)))
            event.accepted = true
          } else if (root.documentActive && (event.key === Qt.Key_Down || event.key === Qt.Key_PageDown)) {
            documentFlick.contentY = Math.min(Math.max(documentFlick.originY,
              documentFlick.originY + documentFlick.contentHeight - documentFlick.height),
              documentFlick.contentY + (event.key === Qt.Key_PageDown ? documentFlick.height * 0.8 : Style.space(48)))
            event.accepted = true
          } else if (!root.documentActive && Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
            if (root.actionPanelActive) root.closeActionPanel()
            else if (root.fileBrowserActive) {
              if (root.fileBrowserPath === "/") {
                if (root.directoryPickerActive) root.workflowBack()
                else root.leaveFileBrowser()
              } else {
                root.fileBrowserPath = root.parentPath(root.fileBrowserPath)
                root.fileEntries = []
                root.selectedIndex = 0
                root.scheduleFileScan()
              }
            } else if (root.workflowActive) root.workflowBack()
            else if (root.focusedExtension) root.leaveFocusedExtension()
            else root.goBack()
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
            if (root.workflowInputActive) root.submitWorkflowInput()
            else if (root.dmenuActive) {
              if (root.mode === "input") root.applyDmenuSelection(root.filterText)
              else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
            } else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (!root.documentActive && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: workflowConfirm
          anchors.fill: parent
          opened: root.workflowConfirmOpen
          z: 10
          message: root.workflowConfirmNode ? (root.workflowConfirmNode.confirm || "Do you want to run " + root.workflowConfirmNode.label + "?") : ""
          confirmText: root.workflowConfirmNode ? root.workflowConfirmNode.confirmLabel : "Run"
          background: root.dialogBackground
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onOpenedChanged: if (opened) { selectedIndex = 1; keyCatcher.forceActiveFocus() }
          onCanceled: { root.workflowConfirmOpen = false; root.workflowConfirmNode = null }
          onConfirmed: {
            var node = root.workflowConfirmNode
            root.workflowConfirmOpen = false
            root.workflowConfirmNode = null
            root.dispatchWorkflowNode(node, "")
          }
        }

        ConfirmDialog {
          id: deleteConfirm

          anchors.fill: parent
          opened: root.deleteConfirmOpen
          z: 10
          message: "Do you want to uninstall " + ((root.deleteTarget && root.deleteTarget.label) || "") + "?"
          confirmText: "Uninstall"
          background: root.dialogBackground
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onOpenedChanged: if (opened) { selectedIndex = 1; keyCatcher.forceActiveFocus() }
          onCanceled: root.cancelDelete()
          onConfirmed: root.confirmDelete()
        }

        ConfirmDialog {
          id: dependencyConfirm

          anchors.fill: parent
          opened: root.dependencyConfirmOpen
          z: 11
          message: root.dependencyTarget
            ? ("Install " + root.dependencyTarget.packageName + " for " + root.dependencyTarget.reason
              + "?\n\nCommand: " + root.dependencyTarget.installCommand.join(" ")
              + "\n\nThe command will run in a visible terminal. Reopen Omalaunch afterward to recheck.")
            : ""
          cancelText: "Not now"
          confirmText: "Install"
          background: root.dialogBackground
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onOpenedChanged: if (opened) { selectedIndex = 1; keyCatcher.forceActiveFocus() }
          onCanceled: root.cancelDependencyInstall()
          onConfirmed: root.confirmDependencyInstall()
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: root.actionBarBottomPadding
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            id: documentHeaderIcon
            visible: root.documentActive && root.activeDocument && root.activeDocument.icon.length > 0
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.activeDocument ? root.activeDocument.icon : ""
            color: root.foreground
            font.family: root.activeDocument && root.activeDocument.iconFont
              ? root.activeDocument.iconFont : root.fontFamily
            font.pixelSize: root.menuItemIconSize
          }

          Text {
            visible: !root.focusedExtension
            anchors.left: documentHeaderIcon.visible ? documentHeaderIcon.right : parent.left
            anchors.leftMargin: documentHeaderIcon.visible ? Style.space(10) : 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.actionPanelActive
              ? ("Actions for " + ((root.actionPanelFile && root.actionPanelFile.name) || "file"))
              : root.fileBrowserActive
                ? (root.fileBrowserPath + (root.filterText ? "  ›  " + root.filterText : ""))
              : root.documentActive
                ? (root.activeDocument ? root.activeDocument.title : root.workflowNode.label)
              : root.workflowActive
                ? root.filterText
              : (root.filterText || (root.dmenuActive ? (root.dmenuPrompt + "…") : ((root.item(root.activeMenu) ? (root.item(root.activeMenu).title || root.item(root.activeMenu).label) : "Go") + "…")))
            color: root.foreground
            opacity: root.documentActive || root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: root.menuItemFontSize
            elide: Text.ElideRight
          }

          Text {
            visible: !!root.focusedExtension
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || root.focusedExtensionPlaceholder()
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: root.menuItemFontSize
            elide: Text.ElideRight
          }

        }

        Text {
          width: parent.width
          height: root.workflowHintHeight
          visible: root.workflowInputActive || root.workflowFilterMenuActive
          text: root.workflowInputActive
            ? root.workflowText(root.workflowNode ? (root.workflowNode.prompt || root.workflowNode.label) : "")
            : ("Search " + root.workflowText(root.workflowNode ? root.workflowNode.label : (root.workflowExtension ? root.workflowExtension.label : "items")))
          color: root.foreground
          opacity: 0.58
          font.family: root.fontFamily
          font.pixelSize: root.menuItemFontSize
          elide: Text.ElideRight
          verticalAlignment: Text.AlignVCenter
        }

        Item {
          width: parent.width
          height: root.visibleRowsHeight

          ListView {
            id: resultList
            visible: !root.documentActive
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
              required property string trailingIcon
              required property string trailingText
              required property string badge
              required property string badgeTone
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
                text: root.isFontSizeSetting(row.itemId) && root.configuredMenuItemFontSize === 0
                  && row.action === root.menuItemFontClass ? "✓" : row.icon
                color: row.hasCursor ? root.selectedText : root.foreground
                font.family: row.iconFont.length > 0 ? row.iconFont : root.fontFamily
                font.pixelSize: root.menuItemIconSize
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
                width: root.menuItemIconSize
                height: root.menuItemIconSize
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
                width: root.menuItemIconSize
                height: root.menuItemIconSize
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
                anchors.left: row.hasIcon ? iconText.right : parent.left
                anchors.leftMargin: row.hasIcon ? Style.space(6) : root.rowReservedBorderLeft + Style.space(18)
                anchors.right: trail.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.max(Style.space(1), Math.round(Style.space(3) * root.menuItemScale))

                Text {
                  id: labelText
                  width: parent.width
                  text: row.label
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.menuItemFontSize
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: root.isFontSizeSetting(row.itemId) && row.index === root.selectedIndex
                    && root.settingsFeedback ? root.settingsFeedback : row.detail
                  visible: (root.filterText || row.kind === "dmenu" || row.itemId === "extension.result.pending"
                    || (root.isFontSizeSetting(row.itemId) && row.index === root.selectedIndex && root.settingsFeedback))
                    && text.length > 0
                  color: root.foreground
                  opacity: 0.52
                  font.family: root.fontFamily
                  font.pixelSize: root.menuSecondaryFontSize
                  elide: Text.ElideRight
                }
              }

              Row {
                id: trail
                width: (row.trailingText.length > 0 ? trailingTextLabel.implicitWidth + Style.space(10) : 0)
                  + (row.badge.length > 0 ? Math.max(Style.space(24), badgeText.implicitWidth + Style.space(12)) + Style.space(6) : 0)
                  + (row.trailingIcon.length > 0 ? Style.space(34) : Style.space(14))
                anchors.right: parent.right
                anchors.rightMargin: root.rowReservedBorderRight + Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
                spacing: Style.space(6)

                Text {
                  id: trailingTextLabel
                  visible: row.trailingText.length > 0
                  text: row.trailingText
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: 0.52
                  font.family: root.fontFamily
                  font.pixelSize: root.menuSecondaryFontSize
                  anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                  visible: row.badge.length > 0
                  width: Math.max(Style.space(24), badgeText.implicitWidth + Style.space(12))
                  height: Math.max(Style.space(24), badgeText.implicitHeight + Style.space(6))
                  radius: height / 2
                  color: Util.alpha(root.badgeToneColor(row.badgeTone), row.hasCursor ? 0.28 : 0.18)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: row.badge
                    color: root.badgeToneColor(row.badgeTone)
                    opacity: 0.92
                    font.family: root.fontFamily
                    font.pixelSize: root.menuSecondaryFontSize
                    font.weight: Font.Medium
                  }
                }

                Text {
                  visible: row.trailingIcon.length > 0
                  text: row.trailingIcon
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: root.menuItemFontSize
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  visible: false
                  text: row.childCount
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: root.menuItemFontSize
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: row.starred ? "★" : (row.kind === "menu" || row.kind === "link" ? "›" : "")
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.starred ? 0.7 : (row.kind === "menu" || row.kind === "link" ? 0.36 : 0)
                  font.family: root.fontFamily
                  font.pixelSize: row.starred ? root.menuSecondaryFontSize : root.menuItemFontSize
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

          Flickable {
            id: documentFlick
            visible: root.documentActive
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: documentColumn.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: documentColumn
              width: documentFlick.width
              spacing: Style.space(16)

              Text {
                width: parent.width
                visible: root.documentLoading || !!root.documentError
                text: root.documentLoading ? "Loading details…" : root.documentError
                color: root.foreground
                opacity: 0.65
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.Wrap
              }

              Text {
                width: parent.width
                visible: root.activeDocument && root.activeDocument.subtitle.length > 0
                text: root.activeDocument ? root.activeDocument.subtitle : ""
                color: root.foreground
                opacity: 0.62
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.Wrap
              }

              Rectangle {
                visible: root.activeDocument && root.activeDocument.status.length > 0
                width: documentStatus.implicitWidth + Style.space(16)
                height: documentStatus.implicitHeight + Style.space(8)
                radius: height / 2
                color: Util.alpha(root.foreground, 0.09)

                Text {
                  id: documentStatus
                  anchors.centerIn: parent
                  text: root.activeDocument ? root.activeDocument.status : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.weight: Font.Medium
                }
              }

              Grid {
                id: documentStats
                width: parent.width
                visible: root.activeDocument && root.activeDocument.stats.length > 0
                columns: width >= Style.space(560) ? 3 : 2
                columnSpacing: Style.space(10)
                rowSpacing: Style.space(10)
                height: visible ? childrenRect.height : 0

                Repeater {
                  model: root.activeDocument ? root.activeDocument.stats : []

                  Rectangle {
                    required property var modelData
                    width: (documentStats.width - documentStats.columnSpacing * (documentStats.columns - 1))
                      / documentStats.columns
                    height: Style.space(68)
                    radius: root.cornerRadius
                    color: Util.alpha(root.foreground, 0.055)

                    Text {
                      id: statIcon
                      visible: modelData.icon.length > 0
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(12)
                      anchors.top: parent.top
                      anchors.topMargin: Style.space(10)
                      text: modelData.icon
                      color: root.foreground
                      opacity: 0.68
                      font.family: modelData.iconFont || root.fontFamily
                      font.pixelSize: root.menuItemIconSize
                    }

                    Column {
                      anchors.left: statIcon.visible ? statIcon.right : parent.left
                      anchors.leftMargin: Style.space(12)
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(10)
                      anchors.top: parent.top
                      anchors.topMargin: Style.space(9)
                      spacing: Style.space(2)

                      Text {
                        width: parent.width
                        text: modelData.value
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: root.menuItemFontSize
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                      }
                      Text {
                        width: parent.width
                        text: modelData.label
                        color: root.foreground
                        opacity: 0.55
                        font.family: root.fontFamily
                        font.pixelSize: root.menuSecondaryFontSize
                        elide: Text.ElideRight
                      }
                    }
                  }
                }
              }

              Column {
                width: parent.width
                visible: root.activeDocument && root.activeDocument.fields.length > 0
                spacing: Style.space(8)

                Repeater {
                  model: root.activeDocument ? root.activeDocument.fields : []

                  Row {
                    required property var modelData
                    width: documentColumn.width
                    spacing: Style.space(14)

                    Text {
                      width: Math.min(Style.space(150), parent.width * 0.3)
                      text: modelData.label
                      color: root.foreground
                      opacity: 0.56
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.Wrap
                    }
                    Text {
                      width: parent.width - x
                      text: modelData.value
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      wrapMode: Text.Wrap
                    }
                  }
                }
              }

              Repeater {
                model: root.activeDocument ? root.activeDocument.sections : []

                Column {
                  required property var modelData
                  width: documentColumn.width
                  spacing: Style.space(7)

                  Row {
                    id: documentSectionHeader
                    width: parent.width
                    height: modelData.heading.length > 0 ? Math.max(sectionHeading.implicitHeight, Style.space(18)) : 0
                    visible: modelData.heading.length > 0
                    spacing: Style.space(10)

                    Text {
                      id: sectionHeading
                      text: modelData.heading
                      color: root.foreground
                      opacity: 0.56
                      font.family: root.fontFamily
                      font.pixelSize: root.menuSecondaryFontSize
                      font.weight: Font.DemiBold
                      font.capitalization: Font.AllUppercase
                      font.letterSpacing: Style.space(1)
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                      width: Math.max(0, documentSectionHeader.width - sectionHeading.implicitWidth
                        - documentSectionHeader.spacing)
                      height: Style.spacing.hairline
                      color: Util.alpha(root.foreground, 0.18)
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                  Text {
                    width: parent.width
                    visible: modelData.format !== "markdown"
                    text: modelData.text
                    color: root.foreground
                    opacity: 0.88
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                  }

                  Column {
                    width: parent.width
                    visible: modelData.format === "markdown"
                    spacing: Style.space(10)

                    Repeater {
                      model: modelData.format === "markdown" ? MenuMarkdown.documentBlocks(modelData.text) : []

                      Item {
                        required property var modelData
                        width: parent ? parent.width : 0
                        height: modelData.kind === "code" ? codeSurface.height : markdownText.implicitHeight

                        Text {
                          id: markdownText
                          visible: modelData.kind === "markdown"
                          width: parent.width
                          text: modelData.html
                          textFormat: Text.RichText
                          color: root.foreground
                          linkColor: root.selectedText
                          opacity: 0.88
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          wrapMode: Text.Wrap
                          onLinkActivated: function(link) { root.openDocumentLink(link) }
                        }

                        Rectangle {
                          id: codeSurface
                          visible: modelData.kind === "code"
                          width: parent.width
                          height: Math.max(Style.space(76), codeText.implicitHeight + Style.space(34))
                          radius: root.cornerRadius
                          color: Util.alpha(root.foreground, 0.065)
                          clip: true

                          Text {
                            visible: modelData.language.length > 0
                            anchors.left: parent.left
                            anchors.leftMargin: Style.space(12)
                            anchors.top: parent.top
                            anchors.topMargin: Style.space(7)
                            text: modelData.language
                            color: root.foreground
                            opacity: 0.42
                            font.family: root.fontFamily
                            font.pixelSize: root.menuCaptionFontSize
                          }

                          Text {
                            id: copyCodeButton
                            anchors.right: parent.right
                            anchors.rightMargin: Style.space(12)
                            anchors.top: parent.top
                            anchors.topMargin: Style.space(7)
                            text: "Copy code"
                            color: root.foreground
                            opacity: copyCodeMouse.containsMouse ? 0.95 : 0.55
                            font.family: root.fontFamily
                            font.pixelSize: root.menuCaptionFontSize

                            MouseArea {
                              id: copyCodeMouse
                              anchors.fill: parent
                              anchors.margins: -Style.space(5)
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.copyDocumentCode(modelData.text)
                            }
                          }

                          Flickable {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: Style.space(12)
                            anchors.rightMargin: Style.space(12)
                            anchors.topMargin: Style.space(27)
                            anchors.bottomMargin: Style.space(9)
                            contentWidth: codeText.implicitWidth
                            contentHeight: height
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Text {
                              id: codeText
                              text: modelData.text
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: root.menuSecondaryFontSize
                              textFormat: Text.PlainText
                              wrapMode: Text.NoWrap
                            }
                          }
                        }
                      }
                    }
                  }
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
              font.pixelSize: root.menuSecondaryFontSize
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
            spacing: Math.max(Style.space(3), Math.round(Style.space(8) * root.menuItemScale))
            visible: !root.focusedExtension && displayModel.count === 0 && root.mode !== "input" && !root.workflowInputActive && (root.filterText || root.activeMenu !== "root") && !root.isPotentialExtensionQuery(root.filterText)

            Text {
              visible: !root.focusedExtension
              text: "󰈉"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Math.max(1, Math.round(Style.font.displayLarge * root.menuItemScale))
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }

            Text {
              text: root.focusedExtension
                ? "Start typing"
                : (root.filterText ? "No matches for “" + root.filterText + "”"
                  : (root.workflowActive && root.workflowNode && root.workflowNode.description
                    ? root.workflowNode.description : "Nothing here yet"))
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Math.max(1, Math.round(Style.font.title * root.menuItemScale))
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }
          }
        }

        Item {
          x: -card.contentLeftInset
          width: parent.width + card.contentLeftInset + card.contentRightInset
          height: root.actionBarHeight
          clip: true

          Rectangle {
            width: parent.width
            height: parent.height + root.actionBarBottomPadding
            color: Util.alpha(root.foreground, 0.035)
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: card.contentRightInset
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(18)

            Repeater {
              model: root.displayedActionBarHints

              Row {
                required property int index
                required property var modelData
                spacing: Style.space(5)
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                  visible: index > 0
                  width: Style.spacing.hairline
                  height: Style.space(15)
                  color: Util.alpha(root.foreground, 0.14)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: modelData.label
                  color: root.foreground
                  opacity: 0.68
                  font.family: root.fontFamily
                  font.pixelSize: root.menuSecondaryFontSize
                  anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                  spacing: Style.space(3)
                  anchors.verticalCenter: parent.verticalCenter

                  Repeater {
                    model: [modelData.shortcut === "Enter" ? "↵" : String(modelData.shortcut)]

                    Item {
                      required property string modelData
                      width: Math.max(height, shortcutText.implicitWidth
                        + Math.max(Style.space(4), Math.round(Style.space(10) * root.menuItemScale)))
                      height: Math.max(Style.space(14), Math.round(Style.space(22) * root.menuItemScale),
                        shortcutText.implicitHeight
                          + Math.max(Style.space(2), Math.round(Style.space(6) * root.menuItemScale)))

                      Rectangle {
                        anchors.fill: parent
                        radius: Math.min(root.cornerRadius,
                          Math.max(Style.space(2), Math.round(Style.space(5) * root.menuItemScale)))
                        color: "transparent"
                        border.width: Style.spacing.hairline
                        border.color: Util.alpha(root.foreground, 0.13)

                        Text {
                          id: shortcutText
                          anchors.centerIn: parent
                          text: modelData
                          color: root.foreground
                          opacity: 0.82
                          font.family: root.fontFamily
                          font.pixelSize: root.menuCaptionFontSize
                          font.weight: Font.Medium
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
