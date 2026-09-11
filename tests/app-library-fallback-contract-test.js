const fs = require('fs')
const path = require('path')
const assert = require('assert')

const menu = fs.readFileSync(path.join(__dirname, '../Menu.qml'), 'utf8')
const access = fs.readFileSync(path.join(__dirname, '../LauncherAppLibrary.qml'), 'utf8')

assert(menu.includes('readonly property var sharedAppLibrary: root.shell ? root.shell.appLibrary : null'))
assert(menu.includes('readonly property var appLibrary: appLibraryAccess.library'))
const integration = menu.match(/  LauncherAppLibrary \{[\s\S]*?\n  \}/)[0]
assert(integration.includes('sharedLibrary: root.sharedAppLibrary'))
assert(!menu.includes('fallbackEnabled') && !access.includes('fallbackEnabled'),
  'fallback selection must not have a separate enable switch')
assert(integration.includes('root.omarchyPath.charAt(0) === "/"'))
assert(integration.includes('Util.fileUrl(root.omarchyPath + "/shell/services/AppLibrary.qml")'))
assert(!integration.includes('providersLoaded'), 'in-place var map mutations must not gate the loader')
assert(access.includes('readonly property var library: root.sharedLibrary ||'),
  'the shared library must take priority')
assert(access.includes('var wanted = !root.sharedLibrary'),
  'fallback activation must not depend on the effective library')
assert(access.includes('fallbackLoader.setSource(root.fallbackSource, { omarchyPath: root.omarchyPath })'),
  'service scans must use the injected installation path from construction')
console.log('App library fallback contract tests passed')
