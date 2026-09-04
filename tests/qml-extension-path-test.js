const fs = require('fs')
const path = require('path')

function assert(condition, message) {
  if (!condition) throw new Error(message)
  console.log(`ok - ${message}`)
}

const qml = fs.readFileSync(path.join(__dirname, '..', 'Menu.qml'), 'utf8')
const favoritesQml = fs.readFileSync(path.join(__dirname, '..', 'LauncherFavorites.qml'), 'utf8')

assert(favoritesQml.includes('Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")')
  && favoritesQml.includes('root.stateHome + "/omarchy/starred-launcher-items.json"'),
'legacy favorite compatibility reads the same XDG state root as startup migration')

const openBody = qml.slice(qml.indexOf('function open(payloadJson)'), qml.indexOf('function close()', qml.indexOf('function open(payloadJson)')))
const resetBody = qml.slice(qml.indexOf('function resetForOpen()'), qml.indexOf('function cancel()', qml.indexOf('function resetForOpen()')))
assert(openBody.indexOf('JSON.parse(payloadJson') < openBody.indexOf('root.resetForOpen()')
  && openBody.indexOf('root.resetForOpen()') < openBody.indexOf('root.openDmenu(payload)')
  && openBody.indexOf('root.resetForOpen()') < openBody.indexOf('root.openRoute('),
'incoming open payload is retained while prior state resets before either requested surface')
assert(resetBody.includes('if (root.dmenuActive && root.requestActive) root.finishRequest(null)')
  && resetBody.indexOf('root.finishRequest(null)') < resetBody.indexOf('root.mode = "menu"'),
'replaced dmenu completion is queued before request fields and mode are reset')
assert(resetBody.includes('MenuModel.openStateReset()') && resetBody.includes('root.resetFileIndex()'),
'menu and dmenu opens share the centralized workflow, picker, file, focus, and action-panel reset path')

assert(qml.includes('MenuModel.focusedPrefixMatch(root.focusedExtension, query)')
  && qml.includes('"extension.focused.prefix"'),
'focused prefix QML path builds one dedicated action row')
assert(qml.includes('action: root.extensionAction(focusedPrefix.extension, focusedPrefix.prompt)'),
'focused prefix QML path uses the literal argument-array substitution action path')
assert(qml.includes('omalaunchDir: root.pluginPath'),
'workflow commands receive the active Omalaunch directory for shared host helpers')
assert(qml.includes('Quickshell.execDetached(command)')
  && qml.includes('MenuModel.workflowClosesOnDispatch(node, command)'),
'terminal workflow leaves detach instead of occupying the reusable action process')
assert(qml.includes('MenuModel.workflowActionIsCurrent(workflowActionProc.generation, root.workflowGeneration'),
'workflow process exits are generation-checked before transitions')
assert(qml.includes('workflowActionProc.running = false')
  && qml.includes('workflowActionKillTimer.restart()')
  && qml.includes('generation !== workflowActionProc.stopGeneration')
  && qml.includes('workflowActionProc.signal(9)'),
'workflow cancellation escalates generation-matched SIGTERM to supported Process SIGKILL')
assert(qml.includes('workflowActionKillTimer.stop()') && qml.includes('workflowActionProc.stopping = false'),
'workflow process exit releases the shared Process and disarms stale escalation')
assert(qml.includes('root.invalidateWorkflowAction("extension catalog changed")')
  && qml.includes('MenuModel.rebindWorkflow(refreshedWorkflow, oldWorkflowStack, oldWorkflowNode)'),
'catalog refresh cancels old actions and rebinds active workflow nodes')
assert(qml.includes('Retained the last known-good extension catalog after a transient loader failure'),
'loader failures retain and diagnose the last known-good QML catalog')
const queryQueueBody = qml.slice(qml.indexOf('function queueExtensionQuery('), qml.indexOf('function collectExtensionQuery('))
const queryDispatchBody = qml.slice(qml.indexOf('function dispatchPendingExtensionQuery('), qml.indexOf('function queueExtensionQuery('))
const queryExitBody = qml.slice(qml.indexOf('id: extensionQueryProc'), qml.indexOf('id: extensionProc'))
assert(queryQueueBody.includes('root.pendingExtensionQuery = {')
  && queryQueueBody.includes('root.stopExtensionQuery("newer query queued")')
  && !queryQueueBody.includes('extensionQueryProc.command ='),
'rapid live queries coalesce into one latest pending request without overwriting a running command')
assert(queryDispatchBody.includes('if (extensionQueryProc.running || extensionQueryProc.stopping')
  && queryDispatchBody.includes('extensionQueryProc.command = request.command'),
'live-query metadata is assigned only while the reusable Process is idle')
assert(queryExitBody.includes('MenuModel.extensionQueryRunIsCurrent(')
  && queryExitBody.includes('var wasStopping = extensionQueryProc.stopping')
  && queryExitBody.indexOf('extensionQueryProc.stopping = false') < queryExitBody.indexOf('root.dispatchPendingExtensionQuery()'),
'live-query exits reject stale output and exclusively dispatch the pending latest request after release')
assert(qml.includes('extensionQueryKillTimer')
  && qml.includes('generation !== extensionQueryProc.stopGeneration')
  && qml.includes('generation !== extensionQueryProc.generation')
  && qml.includes('extensionQueryProc.signal(9)'),
'live-query cancellation escalates SIGTERM with a generation-safe SIGKILL')
assert(qml.includes('root.invalidateExtensionQuery("launcher closed")')
  && qml.includes('root.invalidateExtensionQuery("new launcher session")')
  && qml.includes('root.scheduleExtensionQuery()'),
'close/open and catalog/query context changes invalidate live-query generations')
assert(qml.includes('if (root.directoryPickerActive) root.workflowBack()'),
'directory picker Backspace at filesystem root returns through workflow history')
assert(qml.includes('event.key === Qt.Key_H && (event.modifiers & Qt.ControlModifier)')
  && qml.includes('root.toggleHiddenFiles()')
  && qml.includes('root.fileBrowserShowHidden ? ["--hidden"] : []'),
'Files Ctrl+H rebuilds browsing and search with hidden entries toggled')
const directoryPickerBody = qml.slice(qml.indexOf('function enterDirectoryPicker('), qml.indexOf('function selectWorkflowDirectory('))
assert(directoryPickerBody.includes('root.fileBrowserShowHidden = false')
  && resetBody.includes('root.fileBrowserShowHidden = false'),
'new launcher and directory-picker sessions cannot inherit hidden-file mode')

const dynamicProviderBody = qml.slice(qml.indexOf('id: dynamicMenuProc'), qml.indexOf('id: workflowActionTimeout'))
assert(qml.includes('else if (activation === "menu") root.enterDynamicMenu(extension)')
  && qml.includes('MenuModel.normalizeDynamicMenuOutput(dynamicMenuProc.collected)'),
'dynamic menu roots run a provider and install only normalized snapshots')
assert(dynamicProviderBody.includes('root.dynamicMenuOutputBytes')
  && dynamicProviderBody.includes('dynamicMenuProc.generation !== root.dynamicMenuGeneration')
  && qml.includes('id: dynamicMenuTimeout'),
'dynamic menu providers have output, timeout, and stale-generation bounds')
assert(qml.includes('id: dynamicMenuKillTimer')
  && qml.includes('generation !== dynamicMenuProc.stopGeneration')
  && qml.includes('generation !== dynamicMenuProc.generation')
  && qml.includes('dynamicMenuProc.signal(9)')
  && qml.includes('root.invalidateDynamicMenu()'),
'dynamic menu timeout and output cancellation escalate SIGTERM only for the same provider child')
const submenuProviderBody = qml.slice(qml.indexOf('id: submenuProc'), qml.indexOf('id: documentTimeout'))
assert(qml.includes('function refreshWorkflowSurface()')
  && qml.includes('event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)')
  && qml.includes('documentProc.command = command.slice()')
  && qml.includes('submenuProc.command = command.slice()'),
'Ctrl+R refreshes active dynamic lists and detail documents through their saved direct commands')
assert(qml.includes('function enterSubmenu(node)')
  && qml.includes('MenuModel.normalizeDynamicMenuOutput(submenuProc.collected)')
  && qml.includes('root.enterSubmenu(dynamicSearchEntry.node)'),
'on-demand submenus open from extension menus and global dynamic search')
assert(submenuProviderBody.includes('root.submenuOutputBytes')
  && submenuProviderBody.includes('submenuProc.generation !== root.submenuGeneration')
  && submenuProviderBody.includes('root.workflowNode.id !== submenuProc.submenuNodeId')
  && qml.includes('id: submenuTimeout'),
'submenu providers have output, timeout, capability, row, and stale-generation bounds')
assert(qml.includes('id: submenuKillTimer')
  && qml.includes('generation !== submenuProc.stopGeneration')
  && qml.includes('generation !== submenuProc.generation')
  && qml.includes('submenuProc.signal(9)')
  && qml.includes('root.invalidateSubmenu("workflow navigation changed")'),
'submenu cancellation escalates only for the same direct child and Back invalidates the request')
assert(qml.includes('root.workflowStack.length >= root.workflowMaxDepth'),
'on-demand document and submenu navigation has a host depth bound')

const documentProviderBody = qml.slice(qml.indexOf('id: documentProc'), qml.indexOf('id: dynamicMenuTimeout'))
assert(qml.includes('function enterDocument(node)')
  && qml.includes('MenuModel.normalizeDetailDocument(documentProc.collected)')
  && qml.includes('root.enterDocument(dynamicSearchEntry.node)'),
'on-demand documents open from extension menus and global dynamic search')
assert(documentProviderBody.includes('root.documentOutputBytes')
  && documentProviderBody.includes('documentProc.generation !== root.documentGeneration')
  && documentProviderBody.includes('root.workflowNode.id !== documentProc.documentNodeId')
  && qml.includes('id: documentTimeout'),
'detail providers have output, timeout, capability, row, and stale-generation bounds')
assert(qml.includes('id: documentKillTimer')
  && qml.includes('generation !== documentProc.stopGeneration')
  && qml.includes('generation !== documentProc.generation')
  && qml.includes('documentProc.signal(9)')
  && qml.includes('root.invalidateDocument("workflow navigation changed")'),
'detail cancellation escalates only for the same direct child and Back invalidates the request')
assert(qml.includes('readonly property bool emptyRoot: !root.dmenuActive && !root.workflowActive'),
'detail documents do not collapse into the empty root-menu layout')
assert(qml.includes('required property string badge')
  && qml.includes('required property string badgeTone')
  && qml.includes('id: badgeText')
  && qml.includes('root.badgeToneColor(row.badgeTone)')
  && qml.includes('radius: height / 2'),
'dynamic row badges use a host-rendered trailing pill')
assert(qml.includes('required property string trailingText')
  && qml.includes('id: trailingTextLabel'),
'dynamic rows render always-visible trailing metadata')
assert(qml.includes('id: documentSectionHeader')
  && qml.includes('font.capitalization: Font.AllUppercase')
  && qml.includes('color: Util.alpha(root.foreground, 0.18)'),
'document sections use a distinct uppercase label and divider')
assert(qml.includes('import "MenuMarkdown.js" as MenuMarkdown')
  && qml.includes('MenuMarkdown.documentBlocks(modelData.text)')
  && qml.includes('id: codeSurface')
  && qml.includes('text: "Copy code"')
  && qml.includes('property string hoveredLink: markdownText.linkAt(mouseX, mouseY)')
  && qml.includes('cursorShape: hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor')
  && qml.includes('root.openDocumentLink(link)'),
'Markdown sections render safe rich text with clickable link cursors and separate copyable code blocks')
assert(qml.includes('id: documentHeaderIcon')
  && qml.includes('id: documentStats')
  && qml.includes('model: root.activeDocument ? root.activeDocument.stats : []'),
'detail documents render a header icon and statistic cards')
assert(qml.includes('textFormat: Text.PlainText')
  && qml.includes('model: root.activeDocument ? root.activeDocument.fields : []')
  && qml.includes('model: root.activeDocument ? root.activeDocument.sections : []'),
'detail documents render host-owned structured plain text')

assert(qml.includes('var searchCommand = extension.globalSearchCommand && extension.globalSearchCommand.length > 0')
  && qml.includes('? extension.globalSearchCommand : extension.command'),
'global search preload can use a command independent from the visible extension menu')
assert(qml.includes('var searchNodes = MenuModel.dynamicMenuSearchNodes(workflow)')
  && qml.includes('item: searchItems[i], node: searchNode, items: workflow.items'),
'dedicated global search actions retain the visible menu as their Back destination')

assert(qml.includes('id: dynamicMenuSearchKillTimer')
  && qml.includes('generation !== dynamicMenuSearchProc.stopGeneration')
  && qml.includes('generation !== dynamicMenuSearchProc.generation')
  && qml.includes('dynamicMenuSearchProc.signal(9)')
  && qml.includes('dynamicMenuSearchKillTimer.stop()'),
'global menu preload cancellation escalates SIGTERM safely and disarms stale escalation on exit')
assert(qml.includes(': root.workflowActive\n                ? root.filterText')
  && qml.includes('height: root.workflowHintHeight')
  && qml.includes('visible: root.workflowInputActive || root.workflowFilterMenuActive')
  && qml.includes('root.workflowNode ? (root.workflowNode.prompt || root.workflowNode.label)')
  && qml.includes('? root.workflowNode.label')
  && qml.includes(': "Select an item"'),
'workflow inputs and filterable menus keep context helper text below the typed-value field')
assert(qml.includes('id: pasteProc')
  && qml.includes('["wl-paste", "--no-newline", "--type", "text"]')
  && qml.includes('event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)')
  && qml.includes('event.key === Qt.Key_Insert && (event.modifiers & Qt.ShiftModifier)')
  && qml.includes('root.setFilter((root.filterText + text).substring(0, limit))'),
'workflow inputs accept bounded Ctrl+V and global clipboard text')
assert(qml.includes('root.enterDynamicMenu(extension, true)')
  && qml.includes('if (!retainCurrentRows) root.rebuildDisplay()')
  && qml.includes('dynamicMenuProc.selectionNodeId = retainCurrentRows')
  && qml.includes('Number(displayModel.get(selectedDisplayIndex).action) === selectedWorkflowNodeIndex'),
'dynamic menu mutations retain visible rows and selection until the refreshed provider snapshot is ready')
assert(qml.includes('root.workflowActive && root.selectedWorkflowStarAction && event.key === Qt.Key_S')
  && qml.includes('root.dispatchWorkflowNode(action, "", false, true)'),
'workflow rows with a declared star action support Ctrl+S through the background action lifecycle')
assert(qml.includes('!root.workflowActive && root.selectedDynamicStarAction && event.key === Qt.Key_S')
  && qml.includes('root.dispatchBackgroundAction(extension, action, "")')
  && qml.includes('id: backgroundActionProc')
  && !qml.slice(qml.indexOf('function toggleSelectedDynamicStar()'), qml.indexOf('function openDynamicSearchActions()')).includes('root.workflowActive = true'),
'globally searchable dynamic rows use an independent runner without entering visible workflow state')
assert(qml.includes('workflowRow.starred = workflowChild.starred')
  && qml.includes('if (!starredDynamicEntry.node.starred) continue')
  && qml.includes('starredDynamicRow.starred = true'),
'starred globally searchable dynamic rows appear on the top-level launcher view')
assert(qml.includes('var extensionsDirectory = root.item("extensions")')
  && qml.includes('MenuModel.matchesQuery(extensionsDirectory, preparedQuery, true)'),
'fixed Extensions directory remains explicit in top-level global search during dynamic snapshot rebuilds')
assert(qml.includes('var workflowQuery = MenuModel.prepareSearchQuery(root.filterText.trim())')
  && qml.includes('MenuModel.matchesQuery(workflowItem, workflowQuery, true)')
  && qml.includes('root.workflowNode.items[Number(displayModel.get(root.selectedIndex).action)]'),
'workflow menus filter provider rows while retaining original activation and action identities')
assert(qml.includes('if (rootExtension.available && rootExtension.mode !== "menu") usage.record(row.itemId)'),
'dynamic provider roots do not record usage while static extension behavior remains unchanged')
assert(qml.includes('var dynamicUsageId = MenuModel.dynamicMenuUsageItemId(')
  && qml.includes('dynamicSearchRow.usageCount = usage.count(dynamicUsageId)')
  && qml.includes('dynamicSearchRow.lastUsedAt = usage.lastUsedAt(dynamicUsageId)'),
'dynamic search ranking reads the same provider-owned identity that successful Open records')
assert(qml.includes('function dispatchWorkflowNode(node, input, returnToRoot, backgroundRequested)')
  && qml.includes('workflowActionProc.refreshDynamicMenu = root.workflowExtension.mode === "menu"')
  && qml.includes('workflowActionProc.closeAfter = node.closeOnSuccess')
  && qml.includes('if (workflowActionProc.refreshExtensions) root.loadExtensions(true)'),
'dynamic row mutations reuse tracked workflow actions and refresh successful state')
const workflowExit = qml.slice(qml.indexOf('id: workflowActionProc'), qml.indexOf('id: backgroundActionTimeout'))
assert(workflowExit.includes('if (exitCode !== 0)')
  && workflowExit.includes('if (usageItemId) usage.record(usageItemId)')
  && workflowExit.indexOf('if (exitCode !== 0)') < workflowExit.indexOf('usage.record(usageItemId)')
  && workflowExit.includes('MenuModel.workflowActionIsCurrent'),
'dynamic usage is published only after a successful current foreground action')
const backgroundExit = qml.slice(qml.indexOf('id: backgroundActionProc'), qml.indexOf('id: resultProc'))
assert(backgroundExit.includes('MenuModel.backgroundActionIsCurrent')
  && backgroundExit.includes('if (exitCode !== 0)')
  && backgroundExit.includes('if (usageItemId) usage.record(usageItemId)'),
'background lifecycle rejects stale generations and failed commands before usage publication')
const fileCopyExit = qml.slice(qml.indexOf('id: fileCopyProc'), qml.indexOf('id: pasteProc'))
assert(fileCopyExit.includes('if (exitCode === 0) {')
  && fileCopyExit.includes('root.cancel()')
  && fileCopyExit.includes('root.fileCopyFeedback = "Copy failed"')
  && fileCopyExit.indexOf('root.cancel()') < fileCopyExit.indexOf('root.fileCopyFeedback = "Copy failed"'),
'Files copy completion closes only after success and keeps failure feedback in the open launcher')
assert(qml.includes('function openWorkflowActions()')
  && qml.includes('root.openWorkflowActions()')
  && qml.includes('id: workflowConfirm'),
'dynamic rows expose host-rendered contextual actions and confirmations')
assert(qml.includes('text: MenuMarkdown.colorizeLinks(modelData.html, root.foreground)')
  && qml.includes('linkColor: root.foreground'),
'document links use the normal foreground color')
assert(qml.includes('visible: !root.documentActive && !root.focusedExtension && displayModel.count === 0'),
'document pages suppress the empty menu state')
assert(qml.includes('? Math.max(root.menuItemFontSize, Style.font.heading)')
  && qml.includes('font.weight: root.documentActive ? Font.DemiBold : Font.Normal'),
'document titles use a larger emphasized heading style')
assert(qml.includes('event.key === Qt.Key_K && event.modifiers === Qt.NoModifier')
  && qml.includes('event.key === Qt.Key_J && event.modifiers === Qt.NoModifier'),
'document pages scroll with unmodified K and J keys')
assert((qml.match(/selectedIndex: root\.selectedIndex/g) || []).length === 3
  && qml.includes('Math.min(previous.selectedIndex || 0, displayModel.count - 1)')
  && qml.includes('root.cursorActive = displayModel.count > 0'),
'workflow Back restores the selected source row')
assert(qml.includes('readonly property real menuItemScale: menuItemFontSize / Style.font.body')
  && qml.includes('readonly property int menuItemIconSize: Math.max(Style.space(10), Math.min(Style.space(32),')
  && qml.includes('Math.round(menuItemFontSize * 1.25)')
  && qml.includes('font.pixelSize: root.menuItemIconSize')
  && (qml.match(/width: root\.menuItemIconSize/g) || []).length === 2
  && (qml.match(/height: root\.menuItemIconSize/g) || []).length === 2,
'menu icons and image previews scale with the configured item font size')
assert(qml.includes('property int baseRowHeight: Math.max(Style.space(28), Math.round(Style.space(44) * menuItemScale))')
  && qml.includes('property int detailRowHeight: Math.max(Style.space(36), Math.round(Style.space(52) * menuItemScale))')
  && qml.includes('Math.round(Style.space(18) * menuItemScale)')
  && qml.includes('property int rowSpacing: Math.max(Style.space(1), Math.round(Style.spacing.xs * menuItemScale))'),
'menu row padding and spacing scale with the configured item font size')
assert(qml.includes('property string menuItemFontClass: "title"')
  && qml.includes('? catalog.omalaunchConfig.menuItemFontClass : "title"'),
'menu items use the title theme class when no font override is configured')
assert(qml.includes('event.key === Qt.Key_Comma && (event.modifiers & Qt.ControlModifier)')
  && qml.includes('root.openRoute("settings")')
  && qml.includes('label: "Omalaunch Settings"')
  && qml.includes('label: "Font Size"'),
'Ctrl+Comma opens the built-in Omalaunch font settings menu')
assert(qml.includes('function settingsPageActive()')
  && qml.includes('var settingsSearchScoped = root.settingsPageActive()')
  && qml.includes('settingsSearchScoped ? entry.parent !== active : !root.isDescendantOf(entry.id, active)')
  && qml.includes('var activeExtensionCatalog = settingsSearchScoped ? []')
  && qml.includes('if (!settingsSearchScoped && root.unavailableResultExtension)')
  && qml.includes('root.invalidateExtensionQuery("settings search is locally scoped")'),
'settings searches include only direct children and suppress global extension results')
assert(qml.includes('["compact", "Compact", "bodySmall"]')
  && qml.includes('["small", "Small", "body"]')
  && qml.includes('["default", "Default", "title"]')
  && qml.includes('["large", "Large", "heading"]')
  && qml.includes('["extra-large", "Extra Large", "display"]'),
'font settings expose friendly names for theme font classes')
assert(qml.includes('settingsProc.command = [root.configHelper, "set-font-class", fontClass]')
  && qml.includes('root.configuredMenuItemFontSize = 0')
  && qml.includes('root.settingsFeedback = "Saving…"')
  && qml.includes('root.settingsFeedback = "Could not save font size"')
  && qml.includes('settingsProc.queuedFontClass = fontClass')
  && qml.includes('root.configuredMenuItemFontSize === 0')
  && qml.includes('row.action === root.menuItemFontClass ? "✓" : row.icon'),
'font settings save through the bounded helper and mark the active class')
assert((qml.match(/font\.pixelSize: root\.menuItemFontSize/g) || []).length === 6
  && (qml.match(/font\.pixelSize: root\.menuSecondaryFontSize/g) || []).length === 9
  && qml.includes('font.pixelSize: root.menuCaptionFontSize')
  && qml.includes('property int headerHeight: Math.max(Style.space(28), Math.round(Style.space(34) * menuItemScale))')
  && qml.includes('property int actionBarHeight: Math.max(Style.space(26), Math.round(Style.space(36) * menuItemScale))'),
'search text, item details, and footer content scale with the configured item font size')
assert(qml.includes('readonly property real actionBarFontScale: menuItemFontSize / Style.font.title')
  && qml.includes('Math.round(Style.space(560) * Math.max(1, actionBarFontScale))'),
'action bar compaction accounts for increased footer font sizes')
assert(qml.includes('readonly property int emptyStateHeight:')
  && qml.includes('if (displayModel.count === 0) return root.emptyStateHeight')
  && qml.includes('if (displayModel.count === 0) return Math.max(0, Math.min(root.emptyStateHeight, available))')
  && qml.includes('width: Math.max(0, Math.min(parent.width - Style.space(32), Style.space(420)))')
  && qml.includes('text: root.filterText ? "No results found" : "Nothing here yet"')
  && qml.includes('text: root.filterText ? "Try another search, or press Esc to clear"'),
'empty results use a clear, bounded, helpful state')
assert(qml.includes('font.pixelSize: row.starred ? root.menuSecondaryFontSize : root.menuItemFontSize'),
'trailing menu glyphs scale with the configured item font size')
assert(qml.includes('width: Math.max(height, shortcutText.implicitWidth')
  && qml.includes('Math.round(Style.space(10) * root.menuItemScale)')
  && qml.includes('height: Math.max(Style.space(14), Math.round(Style.space(22) * root.menuItemScale),')
  && qml.includes('Math.round(Style.space(6) * root.menuItemScale)'),
'footer keycaps scale their padding and remain at least as wide as they are tall')
assert(qml.includes('font.pixelSize: Math.max(1, Math.round(Style.font.heading * root.menuItemScale))')
  && qml.includes('font.pixelSize: Math.max(1, Math.round(Style.font.title * root.menuItemScale))')
  && qml.includes('spacing: Math.max(Style.space(4), Math.round(Style.space(7) * root.menuItemScale))'),
'empty-result icon, message, and spacing scale with the configured item font size')
assert(qml.includes('readonly property color dialogBackground: Qt.rgba(background.r, background.g, background.b, 1)')
  && (qml.match(/background: root\.dialogBackground/g) || []).length === 3,
'confirmation cards use one theme-compatible opaque surface')
assert(qml.includes('z: (root.workflowConfirmOpen || root.deleteConfirmOpen || root.dependencyConfirmOpen) ? 20 : 0')
  && (qml.match(/onOpenedChanged: if \(opened\) \{ selectedIndex = 1; keyCatcher\.forceActiveFocus\(\) \}/g) || []).length === 3
  && qml.includes('workflowConfirm.handleKey(event)'),
'confirmation dialogs retain focus, reset the safe button, and route keyboard input')
