const fs = require('fs')
const path = require('path')
const vm = require('vm')

function assert(condition, message) {
  if (!condition) throw new Error(message)
  console.log(`ok - ${message}`)
}

const source = fs.readFileSync(path.join(__dirname, '..', 'MenuDocumentScroll.js'), 'utf8')
const scroll = {}
vm.createContext(scroll)
vm.runInContext(source, scroll)

assert(scroll.nextContentY(100, 0, 1000, 400, 48) === 148,
  'document scroll moves down by one step')
assert(scroll.nextContentY(100, 0, 1000, 400, -48) === 52,
  'document scroll moves up by one step')
assert(scroll.nextContentY(590, 0, 1000, 400, 48) === 600,
  'document scroll clamps repeated down movement to the lower bound')
assert(scroll.nextContentY(10, 0, 1000, 400, -48) === 0,
  'document scroll clamps repeated up movement to the upper bound')
assert(scroll.nextContentY(20, 20, 200, 400, 48) === 20,
  'short documents remain at their nonzero origin')

const qml = fs.readFileSync(path.join(__dirname, '..', 'Menu.qml'), 'utf8')
const keyBody = qml.slice(qml.indexOf('Keys.onPressed: function(event)'), qml.indexOf('ConfirmDialog {', qml.indexOf('Keys.onPressed: function(event)')))
assert(keyBody.includes('event.key === Qt.Key_K && event.modifiers === Qt.NoModifier')
  && keyBody.includes('event.key === Qt.Key_J && event.modifiers === Qt.NoModifier'),
  'only plain K and J join document up and down routing')
assert(keyBody.includes('event.key === Qt.Key_Up || event.key === Qt.Key_PageUp')
  && keyBody.includes('event.key === Qt.Key_Down || event.key === Qt.Key_PageDown'),
  'document arrow and page key routing remains available')
assert(keyBody.indexOf('if (root.workflowConfirmOpen)') < keyBody.indexOf('event.key === Qt.Key_K && event.modifiers === Qt.NoModifier')
  && keyBody.indexOf('if (root.deleteConfirmOpen)') < keyBody.indexOf('event.key === Qt.Key_J && event.modifiers === Qt.NoModifier'),
  'dialogs route keys before document scrolling')
assert(keyBody.indexOf('root.workflowInputActive') < keyBody.indexOf('root.documentActive && (event.key === Qt.Key_Up'),
  'workflow input routing stays before document scrolling')
