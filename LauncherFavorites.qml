import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property string helperPath: ""
  property var extensions: []
  property var providerConfig: ({})
  property bool migrationComplete: false
  property var starredIds: ({})
  property var legacyIds: ({})
  property bool loaded: false
  signal changed()

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
  readonly property string legacyPath: root.stateHome + "/omarchy/starred-launcher-items.json"

  function extensionByCapability(capability) {
    for (var i=0;i<root.extensions.length;i++) if (root.extensions[i].capability===capability) return root.extensions[i]
    return null
  }
  function rebuild() {
    var next=({}), apps=root.providerConfig["omalaunch.apps"] || {favorites:[]}
    for (var a=0;a<apps.favorites.length;a++) next["apps."+apps.favorites[a]]=true
    var filesExt=root.extensionByCapability("files"), files=root.providerConfig["omalaunch.files"] || {favorites:[]}
    if (filesExt && filesExt.id==="omalaunch.files") for (var f=0;f<files.favorites.length;f++) {
      var x=files.favorites[f]
      next["file.favorite:"+JSON.stringify(["files",x.type,x.path])]=true
      next["file.favorite."+x.type+":"+x.path]=true
    }
    var exts=root.providerConfig["omalaunch.extensions"] || {favorites:[]}
    for (var e=0;e<root.extensions.length;e++) if (exts.favorites.indexOf(root.extensions[e].id)>=0)
      next["extension.root:"+JSON.stringify(root.extensions[e].capability)]=true
    if (!root.migrationComplete) for (var id in root.legacyIds) next[id]=true
    root.starredIds=next; root.loaded=true; root.changed()
  }
  function configure(configs, complete) { root.providerConfig=configs || ({}); root.migrationComplete=complete===true; root.rebuild() }
  function isStarred(itemId) { return root.starredIds[String(itemId||"")]===true }
  function target(itemId) {
    var id=String(itemId||"")
    if (id.indexOf("apps.")===0 && id.length>5) return ["omalaunch.apps",id.slice(5)]
    if (id.indexOf("extension.root:")===0) {
      try { var ext=root.extensionByCapability(JSON.parse(id.slice(15))); return ext ? ["omalaunch.extensions",ext.id] : null } catch(e) { return null }
    }
    if (id.indexOf("file.favorite:")===0) {
      try { var p=JSON.parse(id.slice(14)); if (p.length===3 && p[0]==="files") return ["omalaunch.files",p[1]+":"+p[2]] } catch(e) {}
    }
    var match=id.match(/^file\.favorite\.(file|directory):(\/.*)$/)
    return match ? ["omalaunch.files",match[1]+":"+match[2]] : null
  }
  function toggle(itemId) {
    if (!root.loaded || mutation.running) return
    var value=root.target(itemId); if (!value) return
    mutation.command=[root.helperPath,"toggle",value[0],value[1]]; mutation.running=true
  }
  function removeIds(ids) {
    if (!Array.isArray(ids)) return
    for (var i=0;i<ids.length;i++) if (root.isStarred(ids[i])) { root.toggle(ids[i]); return }
  }
  Process {
    id: mutation
    onExited: function(code) { if (code===0) reload.running=true; else console.warn("Omalaunch: provider favorite write failed") }
  }
  Process {
    id: reload
    property string output:""
    stdout: SplitParser { onRead:function(data){ reload.output += data } }
    command: [root.helperPath,"read-all"]
    onExited:function(code) {
      if (code!==0) return
      try { var value=JSON.parse(reload.output); root.providerConfig=value.configs; root.rebuild() } catch(e) {}
      reload.output=""
    }
  }
  FileView {
    id: legacyFile
    path: root.migrationComplete ? "" : root.legacyPath
    printErrors:false
    onLoaded: {
      var next=({}); try { var data=JSON.parse(text()); if(data.version===1&&Array.isArray(data.ids)) for(var i=0;i<data.ids.length;i++) next[data.ids[i]]=true } catch(e) {}
      root.legacyIds=next; root.rebuild()
    }
    onLoadFailed: { root.legacyIds=({}); root.rebuild() }
  }
}
