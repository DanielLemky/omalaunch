function imagePreviewRowsHeight(imagePreviewActive, naturalHeight, minimumHeight, availableHeight) {
  if (!imagePreviewActive) return naturalHeight

  var available = Math.max(0, availableHeight)
  return Math.min(available, Math.max(naturalHeight, minimumHeight))
}

if (typeof module !== "undefined") {
  module.exports = {
    imagePreviewRowsHeight: imagePreviewRowsHeight
  }
}
