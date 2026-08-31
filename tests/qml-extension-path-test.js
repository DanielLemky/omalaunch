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
assert(qml.includes('if (root.directoryPickerActive) root.workflowBack()'),
'directory picker Backspace at filesystem root returns through workflow history')
