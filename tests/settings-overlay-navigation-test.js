#!/usr/bin/env node

const assert = require('assert')
const fs = require('fs')
const path = require('path')
const vm = require('vm')
const MenuModel = require('../MenuModel.js')

const qml = fs.readFileSync(path.join(__dirname, '..', 'Menu.qml'), 'utf8')
const start = qml.indexOf('  function openSettings() {')
const end = qml.indexOf('\n  function ', start + 1)
assert.notStrictEqual(start, -1, 'openSettings exists')
assert.notStrictEqual(end, -1, 'openSettings has a complete body')

const openedAssignments = []
const calls = []
let opened = true
const root = {
  dmenuActive: false,
  workflowActive: true,
  workflowExtension: { id: 'workflow' },
  workflowNode: { kind: 'document' },
  workflowContext: { value: 'old' },
  workflowStack: [{}],
  fileBrowserActive: true,
  directoryPickerActive: true,
  fileBrowserExtension: { id: 'files' },
  fileBrowserPath: '/tmp',
  fileEntries: [{}],
  fileBrowserShowHidden: true,
  actionPanelActive: true,
  actionPanelFile: {},
  focusedExtension: { id: 'search' },
  extensionQuery: 'old',
  extensionResult: 'old',
  resultExtension: {},
  unavailableResultExtension: {},
  workflowConfirmOpen: true,
  workflowConfirmNode: {},
  deleteConfirmOpen: true,
  deleteTarget: {},
  dependencyConfirmOpen: true,
  dependencyTarget: {},
  mode: 'menu',
  requestActive: false,
  selectionFile: '',
  doneFile: '',
  dmenuPrompt: '',
  dmenuOptions: [],
  dmenuRows: [],
  invalidateWorkflowAction: reason => calls.push(['workflow', reason]),
  invalidateBackgroundAction: reason => calls.push(['background', reason]),
  invalidateSubmenu: reason => calls.push(['submenu', reason]),
  invalidateDocument: reason => calls.push(['document', reason]),
  invalidateDynamicMenu: () => calls.push(['dynamic']),
  invalidateExtensionQuery: reason => calls.push(['search', reason]),
  resetFileIndex: () => calls.push(['files']),
  openRoute: route => {
    calls.push(['route', route])
    root.opened = true
  }
}
Object.defineProperty(root, 'opened', {
  get: () => opened,
  set: value => {
    openedAssignments.push(value)
    opened = value
  }
})

const context = { root, MenuModel }
vm.createContext(context)
vm.runInContext(qml.slice(start, end), context)
context.openSettings()

assert.strictEqual(opened, true, 'Settings keeps the overlay open')
assert.deepStrictEqual(openedAssignments, [true],
  'Settings navigation never assigns opened=false during the transition')
for (const name of ['workflow', 'background', 'submenu', 'document', 'dynamic', 'search', 'files'])
  assert(calls.some(call => call[0] === name), `${name} state is canceled`)
assert(calls.some(call => call[0] === 'route' && call[1] === 'settings'),
  'Settings route opens after state cleanup')
assert.strictEqual(root.workflowActive, false)
assert.strictEqual(root.fileBrowserActive, false)
assert.strictEqual(root.focusedExtension, null)
assert.strictEqual(root.extensionQuery, '')
assert.strictEqual(root.workflowConfirmOpen, false)
assert.strictEqual(root.deleteConfirmOpen, false)
assert.strictEqual(root.dependencyConfirmOpen, false)

root.dmenuActive = true
calls.length = 0
openedAssignments.length = 0
context.openSettings()
assert.deepStrictEqual(calls, [], 'Settings navigation does not replace dmenu state')
assert.deepStrictEqual(openedAssignments, [], 'dmenu guard does not change overlay visibility')

console.log('Settings overlay navigation tests passed')
