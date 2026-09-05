#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const files = require('../MenuFiles.js')
const menu = require('../MenuModel.js')

function assert(condition, message) {
  if (!condition) throw new Error(message)
  console.log(`ok - ${message}`)
}

const fileActions = files.actionDefinitions('file', false, true)
assert(fileActions.map(action => action.id).join(',') === 'open,show-files,start-agent,toggle-star,copy-path,copy-file',
  'file actions keep their activation identities and copy-file operation')
assert(files.actionDefinitions('directory', true, true).find(action => action.id === 'toggle-star').label === 'Unstar',
  'directory actions expose the current unstar activation')

const actionItem = action => menu.normalizeItem(`file.action.${action.id}`, {
  label: action.label,
  description: '',
  action: action.id
})
const pathQuery = menu.prepareSearchQuery('projects')
assert(!fileActions.some(action => menu.matchesQuery(actionItem(action), pathQuery, true)),
  'action search does not match the selected file path')
const copyQuery = menu.prepareSearchQuery('copy path')
assert(fileActions.filter(action => menu.matchesQuery(actionItem(action), copyQuery, true)).map(action => action.id).join(',') === 'copy-path',
  'action search matches action labels and keeps the correct activation ID')

const saved = { index: 7, itemId: 'file.item.6', path: '/home/test/projects/report.txt', type: 'file', filter: 'report' }
const restored = files.restoredBrowserState(saved)
assert(restored.filter === 'report' && restored.index === 7 && restored.itemId === 'file.item.6'
  && restored.path === saved.path && restored.type === 'file',
  'Star and Unstar restore the saved Files search and selected row')

const withoutAgent = files.actionDefinitions('directory', false, false)
assert(!withoutAgent.some(action => action.id === 'start-agent')
  && withoutAgent.some(action => action.id === 'open-files')
  && withoutAgent.some(action => action.id === 'copy-path'),
  'missing optional agent tools remove only Start Agent Here')

const qml = fs.readFileSync(path.join(__dirname, '..', 'Menu.qml'), 'utf8')
assert(qml.includes('root.closeActionPanel()')
  && qml.includes('root.pendingStarSelectionId = restored.itemId')
  && qml.includes('description: ""'),
  'QML uses the tested restoration and label-only action search paths')
assert(qml.includes("shutil.which('omarchy-agent')")
  && qml.includes("shutil.which('omarchy-default-agent')")
  && qml.includes('root.agentToolsAvailable = exitCode === 0'),
  'QML checks both optional agent tools without changing Files availability')
