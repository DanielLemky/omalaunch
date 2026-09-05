const fs = require('fs')
const vm = require('vm')
const assert = require('assert')
const qml = fs.readFileSync(require('path').join(__dirname, '../Menu.qml'), 'utf8')
const start = qml.indexOf('  function selectOpeningScreen() {')
const end = qml.indexOf('\n  }', start) + 4
const screens = [{name: 'laptop'}, {name: 'external'}]
const root = {opened: false, openingScreen: null}
const Hyprland = {focusedMonitor: {name: 'external'}}
const context = {root, Hyprland, Quickshell: {screens}}
vm.createContext(context)
vm.runInContext(qml.slice(start, end), context)
context.selectOpeningScreen()
assert.strictEqual(root.openingScreen, screens[1])
root.opened = true
Hyprland.focusedMonitor.name = 'laptop'
context.selectOpeningScreen()
assert.strictEqual(root.openingScreen, screens[1], 'do not move an open overlay')
root.opened = false
context.selectOpeningScreen()
assert.strictEqual(root.openingScreen, screens[0])
Hyprland.focusedMonitor = null
context.selectOpeningScreen()
assert.strictEqual(root.openingScreen, screens[0])
context.Quickshell.screens = []
context.selectOpeningScreen()
assert.strictEqual(root.openingScreen, null)
assert.strictEqual((qml.match(/root\.selectOpeningScreen\(\)\n    opened = true/g) || []).length, 2)
assert(qml.includes('screen: root.openingScreen'))
console.log('Opening screen tests passed')
