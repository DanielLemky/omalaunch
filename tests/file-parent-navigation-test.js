const fs = require('fs')
const path = require('path')
const MenuModel = require('../MenuModel.js')

function assert(condition, message) {
  if (!condition) throw new Error(message)
  console.log(`ok - ${message}`)
}

const qml = fs.readFileSync(path.join(__dirname, '..', 'Menu.qml'), 'utf8')

function qmlFunction(name, arguments_) {
  const marker = `function ${name}(`
  const start = qml.indexOf(marker)
  if (start < 0) throw new Error(`missing ${name}`)
  const bodyStart = qml.indexOf('{', start)
  let depth = 0
  let end = bodyStart
  for (; end < qml.length; end++) {
    if (qml[end] === '{') depth++
    else if (qml[end] === '}' && --depth === 0) break
  }
  return new Function(...arguments_, qml.slice(bodyStart + 1, end))
}

const navigateParent = qmlFunction('navigateFileBrowserParent', ['root'])
const activateIndex = qmlFunction('activateIndex', ['root', 'displayModel', 'MenuModel', 'usage', 'Qt', 'keyCatcher', 'index', 'fromPointer'])
const footerActionAvailable = qmlFunction('footerActionAvailable', ['root', 'id'])
const triggerFooterAction = qmlFunction('triggerFooterAction', ['root', 'displayModel', 'id'])

function navigationState() {
  const root = {
    fileBrowserPath: '/home/test',
    filterText: 'parent',
    fileEntries: [{ name: 'stale' }],
    selectedIndex: 0,
    fileBrowserActive: true,
    directoryPickerActive: false,
    workflowActive: false,
    actionPanelActive: false,
    deleteConfirmOpen: false,
    dmenuActive: false,
    cursorActive: true,
    dynamicMenuSearchEntry: () => null,
    extensionForRootId: () => null,
    parentPath: value => value.substring(0, value.lastIndexOf('/')) || '/',
    scheduleFileScan() {
      this.scan = { path: this.fileBrowserPath, filter: this.filterText }
    }
  }
  root.navigateFileBrowserParent = () => navigateParent(root)
  return root
}

const parentItem = MenuModel.normalizeItem('file.navigation.parent', {
  icon: '󱧰', label: 'Parent directory', description: '/home', action: '/home'
})
const parentRow = MenuModel.displayRow({}, [], {}, parentItem, parentItem.description, -2, '', {})
assert(parentRow.itemId === 'file.navigation.parent' && parentRow.kind === 'action',
  'the parent result is an actionable row')

const displayModel = { count: 1, get: index => index === 0 ? parentRow : null }
const usage = { record() { throw new Error('parent navigation must not record usage') } }

const clickRoot = navigationState()
activateIndex(clickRoot, displayModel, MenuModel, usage, {}, {}, 0, true)
assert(clickRoot.fileBrowserPath === '/home' && clickRoot.filterText === ''
  && clickRoot.fileEntries.length === 0 && clickRoot.scan.path === '/home' && clickRoot.scan.filter === '',
  'click activation navigates up and scans the parent without the old filter')

const enterRoot = navigationState()
enterRoot.actionBarHints = MenuModel.actionBarHints({
  fileBrowserActive: true,
  fileSelectionType: 'directory',
  hasSelection: true,
  fileActionsAvailable: false,
  primaryActionLabel: 'Go up'
})
enterRoot.footerActionAvailable = id => footerActionAvailable(enterRoot, id)
enterRoot.activateIndex = index => activateIndex(enterRoot, displayModel, MenuModel, usage, {}, {}, index, false)
assert(enterRoot.actionBarHints.map(hint => hint.id).join(',') === 'primary'
  && enterRoot.actionBarHints[0].label === 'Go up',
  'the selected parent row has only an available primary footer action')
assert(triggerFooterAction(enterRoot, displayModel, 'primary') === true
  && enterRoot.fileBrowserPath === '/home' && enterRoot.filterText === ''
  && enterRoot.scan.path === '/home' && enterRoot.scan.filter === '',
  'Enter activation uses the primary action, navigates up, and clears the scan filter')

assert(parentItem.icon.codePointAt(0) === 0xF19F0,
  'the parent row uses Nerd Font md-folder_arrow_up at U+F19F0')
