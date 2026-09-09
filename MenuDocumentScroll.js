function nextContentY(currentY, originY, contentHeight, viewportHeight, delta) {
  var minimumY = originY
  var maximumY = Math.max(minimumY, minimumY + contentHeight - viewportHeight)
  return Math.max(minimumY, Math.min(maximumY, currentY + delta))
}
