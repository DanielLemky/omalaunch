const fs = require('fs')
const path = require('path')
const vm = require('vm')
const assert = require('assert')

const qml = fs.readFileSync(path.join(__dirname, '../Menu.qml'), 'utf8')
const start = qml.indexOf('  function resetAppIconRefreshState() {')
const end = qml.indexOf('\n  function badgeToneColor(', start)
assert(start >= 0 && end > start, 'icon refresh functions must be present')

let now = 1000
const root = {
  appLibrary: null,
  appIconRefreshTtlMs: 30000,
  appIconIndexUpdatedAt: 0,
  appIconRefreshPending: false
}
const context = { root, Date: { now: () => now } }
vm.createContext(context)
vm.runInContext(qml.slice(start, end), context)
root.resetAppIconRefreshState = context.resetAppIconRefreshState
root.completeAppIconRefresh = context.completeAppIconRefresh
root.appIconRefreshHasCompletionSignal = context.appIconRefreshHasCompletionSignal

let rawRefreshes = 0
const rawAppLibrary = { iconIndex: {}, refreshIcons: () => rawRefreshes++ }
root.appLibrary = rawAppLibrary
context.refreshAppIconsIfStale()
assert.strictEqual(rawRefreshes, 1)
assert.strictEqual(root.appIconRefreshPending, true,
  'raw AppLibrary waits for iconIndexChanged')
context.refreshAppIconsIfStale()
assert.strictEqual(rawRefreshes, 1, 'a pending raw scan is not restarted')
now = 2000
context.completeAppIconRefresh()
assert.strictEqual(root.appIconRefreshPending, false)
assert.strictEqual(root.appIconIndexUpdatedAt, now)
now = 31999
context.refreshAppIconsIfStale()
assert.strictEqual(rawRefreshes, 1, 'raw refreshes stay bounded by the TTL')
now = 32000
context.refreshAppIconsIfStale()
assert.strictEqual(rawRefreshes, 2)

// App-library replacement runs resetAppIconRefreshState through
// onAppLibraryChanged. Exercise that reset before attaching the proxy.
context.resetAppIconRefreshState()
let proxyRefreshes = 0
const proxyAppLibrary = { refreshIcons: () => proxyRefreshes++ }
root.appLibrary = proxyAppLibrary
now = 50000
context.refreshAppIconsIfStale()
assert.strictEqual(proxyRefreshes, 1)
assert.strictEqual(root.appIconRefreshPending, false,
  'a proxy without iconIndexChanged must never stay pending')
assert.strictEqual(root.appIconIndexUpdatedAt, now,
  'proxy dispatch starts its bounded freshness interval')
now = 79999
context.refreshAppIconsIfStale()
assert.strictEqual(proxyRefreshes, 1)
now = 80000
context.refreshAppIconsIfStale()
assert.strictEqual(proxyRefreshes, 2)

// A second replacement must clear proxy freshness before raw attachment.
context.resetAppIconRefreshState()
root.appLibrary = rawAppLibrary
now = 81000
context.refreshAppIconsIfStale()
assert.strictEqual(rawRefreshes, 3, 'reattached raw API refreshes immediately')
assert.strictEqual(root.appIconRefreshPending, true)

const connections = qml.slice(qml.indexOf('  Connections {\n    target: root.appLibrary'))
assert(connections.includes('ignoreUnknownSignals: true'),
  'the optional raw-only signal must not warn on the proxy API')
console.log('App icon refresh compatibility tests passed')
