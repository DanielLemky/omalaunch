const fs = require('fs')
const path = require('path')
const vm = require('vm')

function assert(condition, message) {
  if (!condition) throw new Error(message)
  console.log(`ok - ${message}`)
}

const qml = fs.readFileSync(path.join(__dirname, '..', 'Menu.qml'), 'utf8')

function qmlFunction(name) {
  const start = qml.indexOf(`function ${name}(`)
  if (start < 0) throw new Error(`missing ${name}`)
  const open = qml.indexOf('{', start)
  let depth = 0
  for (let index = open; index < qml.length; index++) {
    if (qml[index] === '{') depth++
    if (qml[index] === '}' && --depth === 0)
      return qml.slice(start, index + 1).replace(`function ${name}`, 'function')
  }
  throw new Error(`unterminated ${name}`)
}

const root = {
  filterText: '',
  dmenuActive: false,
  workflowFilterMenuActive: false,
  baseRowHeight: 44,
  detailRowHeight: 52
}
const context = vm.createContext({ root })
root.rowShowsDetail = vm.runInContext(`(${qmlFunction('rowShowsDetail')})`, context)
const rowHeightForDetail = vm.runInContext(`(${qmlFunction('rowHeightForDetail')})`, context)

root.workflowFilterMenuActive = true
assert(root.rowShowsDetail('owner/repository'),
  'workflow rows show nonempty descriptions while browsing without a filter')
assert(rowHeightForDetail('owner/repository') === root.detailRowHeight,
  'unfiltered workflow rows reserve the matching two-line height')

root.filterText = 'repo'
assert(root.rowShowsDetail('owner/repository')
  && rowHeightForDetail('owner/repository') === root.detailRowHeight,
'filtered workflow rows keep visible descriptions and two-line height')

root.workflowFilterMenuActive = false
root.filterText = ''
assert(!root.rowShowsDetail('ordinary detail')
  && rowHeightForDetail('ordinary detail') === root.baseRowHeight,
'ordinary static rows keep their one-line browsing presentation')

root.filterText = 'ordinary'
assert(root.rowShowsDetail('ordinary detail')
  && rowHeightForDetail('ordinary detail') === root.detailRowHeight,
'filtered static rows keep their existing description and height')

root.filterText = ''
root.dmenuActive = true
assert(root.rowShowsDetail('caller subtext')
  && rowHeightForDetail('caller subtext') === root.detailRowHeight,
'dmenu rows keep their existing description and height')

root.workflowFilterMenuActive = true
assert(!root.rowShowsDetail('') && rowHeightForDetail('') === root.baseRowHeight,
'empty workflow descriptions keep one-line height')

assert(qml.includes('visible: (root.rowShowsDetail(text)')
  && qml.includes('return root.rowShowsDetail(detail) ? root.detailRowHeight : root.baseRowHeight'),
'row visibility and row height use the same detail decision')
