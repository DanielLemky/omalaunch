const fs = require('fs')
const path = require('path')

function assert(condition, message) {
  if (!condition) throw new Error(message)
  console.log(`ok - ${message}`)
}

const qml = fs.readFileSync(path.join(__dirname, '..', 'Menu.qml'), 'utf8')

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
assert(qml.includes('id: dynamicMenuSearchKillTimer')
  && qml.includes('generation !== dynamicMenuSearchProc.stopGeneration')
  && qml.includes('generation !== dynamicMenuSearchProc.generation')
  && qml.includes('dynamicMenuSearchProc.signal(9)')
  && qml.includes('dynamicMenuSearchKillTimer.stop()'),
'global menu preload cancellation escalates SIGTERM safely and disarms stale escalation on exit')
assert(qml.includes(': root.workflowActive\n                ? root.filterText')
  && qml.includes('height: root.workflowHintHeight')
  && qml.includes('visible: root.workflowInputActive || root.workflowFilterMenuActive')
  && qml.includes('root.workflowNode.prompt || root.workflowNode.label')
  && qml.includes('"Search " + root.workflowText'),
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
assert(qml.includes('function dispatchWorkflowNode(node, input, returnToRoot, backgroundRequested)')
  && qml.includes('workflowActionProc.refreshDynamicMenu = root.workflowExtension.mode === "menu"')
  && qml.includes('workflowActionProc.closeAfter = node.closeOnSuccess')
  && qml.includes('if (workflowActionProc.refreshExtensions) root.loadExtensions(true)'),
'dynamic row mutations reuse tracked workflow actions and refresh successful state')
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
assert(qml.includes('readonly property color dialogBackground: Qt.rgba(background.r, background.g, background.b, 1)')
  && (qml.match(/background: root\.dialogBackground/g) || []).length === 3,
'confirmation cards use one theme-compatible opaque surface')
assert(qml.includes('z: (root.workflowConfirmOpen || root.deleteConfirmOpen || root.dependencyConfirmOpen) ? 20 : 0')
  && (qml.match(/onOpenedChanged: if \(opened\) \{ selectedIndex = 1; keyCatcher\.forceActiveFocus\(\) \}/g) || []).length === 3
  && qml.includes('workflowConfirm.handleKey(event)'),
'confirmation dialogs retain focus, reset the safe button, and route keyboard input')
