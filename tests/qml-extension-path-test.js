const fs = require('fs')
const path = require('path')

function assert(condition, message) {
  if (!condition) throw new Error(message)
  console.log(`ok - ${message}`)
}

const qml = fs.readFileSync(path.join(__dirname, '..', 'Menu.qml'), 'utf8')

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
assert(qml.includes('root.invalidateWorkflowAction("extension catalog changed")')
  && qml.includes('MenuModel.rebindWorkflow(refreshedWorkflow, oldWorkflowStack, oldWorkflowNode)'),
'catalog refresh cancels old actions and rebinds active workflow nodes')
assert(qml.includes('Retained the last known-good extension catalog after a transient loader failure'),
'loader failures retain and diagnose the last known-good QML catalog')
assert(qml.includes('if (root.directoryPickerActive) root.workflowBack()'),
'directory picker Backspace at filesystem root returns through workflow history')
