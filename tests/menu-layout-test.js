#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const layout = require('../MenuLayout.js')

function assertEqual(actual, expected, message) {
  if (actual !== expected) throw new Error(`${message}: expected ${expected}, got ${actual}`)
  console.log(`ok - ${message}`)
}

const emptyState = {
  documentActive: false,
  focusedExtension: null,
  displayCount: 0,
  mode: 'menu',
  workflowInputActive: false,
  actionPanelActive: false,
  dialogOpen: false,
  potentialExtensionQuery: false,
  filterText: '',
  activeMenu: 'root',
  workflowMenuActive: false
}
assertEqual(layout.emptyStateVisible(emptyState), false,
  'an ordinary empty root does not show an empty-state panel')
assertEqual(layout.emptyStateVisible({ ...emptyState, workflowMenuActive: true }), true,
  'a loading dynamic provider root can show its empty-state panel')
assertEqual(layout.emptyStateVisible({ ...emptyState, workflowMenuActive: true, activeMenu: 'submenu' }), true,
  'a loading dynamic submenu can show its empty-state panel')
assertEqual(layout.emptyStateVisible({ ...emptyState, filterText: 'missing' }), true,
  'an ordinary filtered root keeps its no-results panel')
assertEqual(layout.emptyStateVisible({ ...emptyState, workflowMenuActive: true, actionPanelActive: true }), false,
  'an unfiltered action-panel transition hides the underlying workflow empty state')
assertEqual(layout.emptyStateVisible({ ...emptyState, activeMenu: 'settings', actionPanelActive: true }), false,
  'an unfiltered settings action panel hides its empty state')
assertEqual(layout.emptyStateVisible({ ...emptyState, actionPanelActive: true, filterText: 'missing' }), true,
  'a filtered action panel shows its no-results state')
assertEqual(layout.emptyStateVisible({ ...emptyState, activeMenu: 'settings', actionPanelActive: true, filterText: 'missing' }), true,
  'a filtered settings action panel shows its no-results state')
assertEqual(layout.emptyStateVisible({ ...emptyState, actionPanelActive: true, filterText: 'missing', focusedExtension: {} }), false,
  'a focused extension still hides the filtered action-panel empty state')
assertEqual(layout.emptyStateVisible({ ...emptyState, actionPanelActive: true, filterText: 'missing', dialogOpen: true }), false,
  'a dialog still hides the filtered action-panel empty state')
assertEqual(layout.emptyStateVisible({ ...emptyState, workflowMenuActive: true, documentActive: true }), false,
  'document loading hides the menu empty state')
assertEqual(layout.emptyStateVisible({ ...emptyState, workflowMenuActive: true, potentialExtensionQuery: true }), false,
  'a potential extension query hides the menu empty state')
assertEqual(layout.emptyStateVisible({ ...emptyState, actionPanelActive: true, filterText: 'missing', potentialExtensionQuery: true }), false,
  'a potential extension query still hides the filtered action-panel empty state')

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
if (!qml.includes('visible: MenuLayout.emptyStateVisible({')
    || !qml.includes('actionPanelActive: root.actionPanelActive,\n              dialogOpen: root.workflowConfirmOpen || root.deleteConfirmOpen || root.dependencyConfirmOpen,\n              potentialExtensionQuery: root.isPotentialExtensionQuery(root.filterText),\n              filterText: root.filterText,')
    || !qml.includes('workflowMenuActive: root.workflowActive && root.workflowNode && root.workflowNode.kind === "menu"')
    || !qml.includes('text: parent.loading ? "Loading…" : (root.filterText ? "No results found" : "Nothing here yet")')
    || !qml.includes('root.dynamicMenuLoading || root.submenuLoading')) {
  throw new Error('Menu.qml does not show distinct loading feedback for empty dynamic menus')
}
console.log('ok - Menu.qml uses the tested dynamic-menu empty-state rule')
