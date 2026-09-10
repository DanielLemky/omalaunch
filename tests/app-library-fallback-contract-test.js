const fs = require('fs')
const path = require('path')
const assert = require('assert')

const menu = fs.readFileSync(path.join(__dirname, '../Menu.qml'), 'utf8')
const access = fs.readFileSync(path.join(__dirname, '../LauncherAppLibrary.qml'), 'utf8')

assert(menu.includes('readonly property var sharedAppLibrary: root.shell ? root.shell.appLibrary : null'))
assert(menu.includes('readonly property var appLibrary: appLibraryAccess.library'))
const integration = menu.match(/  LauncherAppLibrary \{[\s\S]*?\n  \}/)[0]
assert(integration.includes('sharedLibrary: root.sharedAppLibrary'))
assert(integration.includes('fallbackEnabled: root.shell !== null'))
assert(integration.includes('root.omarchyPath.charAt(0) === "/"'))
assert(integration.includes('Util.fileUrl(root.omarchyPath + "/shell/services/AppLibrary.qml")'))
assert(!integration.includes('providersLoaded'), 'in-place var map mutations must not gate the loader')
assert(access.includes('readonly property var library: root.sharedLibrary\n    ||'),
  'the shared library must take priority')
assert(access.includes('var wanted = root.fallbackEnabled && !root.sharedLibrary'),
  'fallback activation must not depend on the effective library')
assert(access.includes('fallbackLoader.setSource(root.fallbackSource, { omarchyPath: root.omarchyPath })'),
  'service scans must use the injected installation path from construction')
const reconcile = menu.slice(menu.indexOf('  onAppLibraryChanged:'), menu.indexOf('  property bool deleteConfirmOpen:'))
assert(reconcile.includes('appRowsMergeDebounce.restart()'), 'library changes must schedule the owned reconciliation timer')
assert(!reconcile.includes('Qt.callLater'), 'library teardown must not queue callbacks that outlive the menu')
assert(menu.includes('onTriggered: if (root.providersLoaded["apps"]) root.mergeAppRows()'),
  'the owned timer must reconcile only the current loaded provider')
console.log('App library fallback contract tests passed')
