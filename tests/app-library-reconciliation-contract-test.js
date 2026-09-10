const fs = require('fs')
const path = require('path')
const assert = require('assert')

// Permanent regression coverage. This test must not depend on the temporary
// app-library fallback component or its fixtures.
const menu = fs.readFileSync(path.join(__dirname, '../Menu.qml'), 'utf8')
const start = menu.indexOf('  onAppLibraryChanged:')
const end = menu.indexOf('  property bool deleteConfirmOpen:', start)
assert(start >= 0 && end > start, 'app-library change handler must be present')
const reconcile = menu.slice(start, end)
assert(reconcile.includes('appRowsMergeDebounce.restart()'), 'library changes must schedule the owned reconciliation timer')
assert(!reconcile.includes('Qt.callLater'), 'library teardown must not queue callbacks that outlive the menu')
assert(menu.includes('onTriggered: if (root.providersLoaded["apps"]) root.mergeAppRows()'),
  'the owned timer must reconcile only the current loaded provider')
console.log('App library reconciliation contract tests passed')
