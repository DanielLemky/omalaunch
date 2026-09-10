import QtQuick

// Temporary compatibility path for hosts that omit the menu app-library API.
// Upstream fix: https://github.com/omacom/omarchy/pull/11075
// Remove when our minimum supported Omarchy version includes that fix.
// See APP-LIBRARY-COMPATIBILITY.md for the removal checklist.
// The fallback is an independent instance of the installed Omarchy service,
// not a reference to the host's private object tree.
Item {
  id: root

  property var sharedLibrary: null
  property bool fallbackEnabled: false
  property url fallbackSource: ""
  property string omarchyPath: ""
  readonly property var library: root.sharedLibrary
    || (root.fallbackEnabled ? fallbackLoader.item : null)
  readonly property int fallbackStatus: fallbackLoader.status
  property bool componentReady: false
  property string loadedOmarchyPath: ""

  function releaseFallback() {
    var owned = fallbackLoader.item
    // The service can leave a duration-0 launch OSD open. Stop its launch
    // timers and close only its own feedback before the Loader destroys it.
    if (owned && typeof owned.closeLaunchFeedback === "function") {
      try {
        owned.closeLaunchFeedback(owned.launchSerial)
      } catch (error) {
        console.warn("Omalaunch: fallback launch feedback cleanup failed:", error)
      }
    }
    fallbackLoader.active = false
    fallbackLoader.source = ""
    root.loadedOmarchyPath = ""
  }

  function syncFallback() {
    if (!root.componentReady) return
    var wanted = root.fallbackEnabled && !root.sharedLibrary
      && String(root.fallbackSource).length > 0
    if (wanted && fallbackLoader.active
        && String(fallbackLoader.source) === String(root.fallbackSource)
        && root.loadedOmarchyPath === root.omarchyPath) return
    root.releaseFallback()
    if (!wanted) return
    root.loadedOmarchyPath = root.omarchyPath
    // Set properties before Component.onCompleted starts the service scans.
    fallbackLoader.setSource(root.fallbackSource, { omarchyPath: root.omarchyPath })
    fallbackLoader.active = true
  }

  onSharedLibraryChanged: root.syncFallback()
  onFallbackEnabledChanged: root.syncFallback()
  onFallbackSourceChanged: root.syncFallback()
  onOmarchyPathChanged: root.syncFallback()

  Loader {
    id: fallbackLoader
    active: false
    asynchronous: true
    onStatusChanged: {
      if (status === Loader.Error)
        console.warn("Omalaunch: fallback app library could not load:", source)
    }
  }

  Component.onCompleted: {
    root.componentReady = true
    root.syncFallback()
  }
  Component.onDestruction: {
    root.componentReady = false
    root.releaseFallback()
  }
}
