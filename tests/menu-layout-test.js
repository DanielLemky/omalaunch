#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const layout = require('../MenuLayout.js')

function assertEqual(actual, expected, message) {
  if (actual !== expected) throw new Error(`${message}: expected ${expected}, got ${actual}`)
  console.log(`ok - ${message}`)
}

assertEqual(layout.imagePreviewRowsHeight(true, 92, 340, 480), 340,
  'few image rows use the theme-scaled preview minimum')
assertEqual(layout.imagePreviewRowsHeight(true, 430, 340, 480), 430,
  'many image rows keep their natural height')
assertEqual(layout.imagePreviewRowsHeight(true, 92, 340, 236), 236,
  'a small screen bounds the preview above the footer')
assertEqual(layout.imagePreviewRowsHeight(false, 92, 340, 480), 92,
  'a non-image selection keeps its compact natural height')

const qml = fs.readFileSync(path.join(__dirname, '..', 'Menu.qml'), 'utf8')
if (!qml.includes('readonly property int imagePreviewMinRowsHeight: Style.space(340)')
    || !qml.includes('MenuLayout.imagePreviewRowsHeight(root.imagePreviewActive,')) {
  throw new Error('Menu.qml does not use the shared theme-scaled image preview layout rule')
}
console.log('ok - Menu.qml uses the tested image preview layout rule')
