function emptyStateVisible(state) {
  if (state.documentActive || state.focusedExtension || state.displayCount !== 0
      || state.mode === "input" || state.workflowInputActive || state.actionPanelActive
      || state.dialogOpen || state.potentialExtensionQuery) return false

  return !!state.filterText || state.activeMenu !== "root" || state.workflowMenuActive
}

function imagePreviewRowsHeight(imagePreviewActive, naturalHeight, minimumHeight, availableHeight) {
  if (!imagePreviewActive) return naturalHeight

  var available = Math.max(0, availableHeight)
  return Math.min(available, Math.max(naturalHeight, minimumHeight))
}

if (typeof module !== "undefined") {
  module.exports = {
    emptyStateVisible: emptyStateVisible,
    imagePreviewRowsHeight: imagePreviewRowsHeight
  }
}
