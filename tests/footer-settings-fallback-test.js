const fs = require('fs')
const vm = require('vm')
const assert = require('assert')
const menu = require('../MenuModel.js')
const qml = fs.readFileSync(require('path').join(__dirname, '../Menu.qml'), 'utf8')
const start = qml.indexOf('  function handleFooterShortcut(event) {')
const end = qml.indexOf('\n  function ', start + 1)
let opened = 0
let available = false
const root = { dmenuActive: false, triggerFooterAction: () => available, openSettings: () => opened++ }
const context = { root, MenuModel: menu, Qt: { Key_Return: 1000, Key_Enter: 1001, ControlModifier: 4 }, String }
vm.createContext(context)
vm.runInContext(qml.slice(start, end), context)
assert.strictEqual(context.handleFooterShortcut({ key: 44, modifiers: 4 }), true)
assert.strictEqual(opened, 1)
available = true
assert.strictEqual(context.handleFooterShortcut({ key: 44, modifiers: 4 }), true)
assert.strictEqual(opened, 1, 'an available footer action takes precedence')
available = false
root.dmenuActive = true
assert.strictEqual(context.handleFooterShortcut({ key: 44, modifiers: 4 }), false)
assert.strictEqual(opened, 1, 'dmenu does not open global settings')
console.log('Footer Settings fallback tests passed')
