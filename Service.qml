import QtQuick
import Quickshell
import Quickshell.Io

// Chroma service: keeps GTK/Qt in step with Omarchy.
// Generation lives in bin/chroma-apply; the theme-set.d hook runs it on every
// switch. This service only (re)installs wiring once at shell start — it does
// *not* probe+reapply on a timer (that fought the hook and made boots/theme
// flips feel like the shell was having a stroke).
Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/chroma"
  readonly property string pluginDir: manifest && manifest.__sourceDir
    ? manifest.__sourceDir
    : home + "/.config/omarchy/plugins/io.github.alxwolfenstein97.chroma"

  property var state: null
  property string lastError: ""

  readonly property string themeName: state && state.theme ? String(state.theme) : ""
  readonly property string mode: state && state.mode ? String(state.mode) : ""
  readonly property var palette: state && state.palette ? state.palette : null
  readonly property string rootStatus: state && state.root && state.root.status
    ? String(state.root.status) : ""

  FileView {
    path: root.stateDir + "/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseState(text())
    onLoadFailed: root.state = null
  }

  function parseState(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      root.state = parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      console.warn("chroma", "Ignoring bad state.json", e)
      root.state = null
    }
  }

  Process {
    id: installer
    running: false
    // Pull adw-gtk-theme when missing — plugin add only enables the service;
    // this is the first real install.sh pass for most users.
    command: ["bash", root.pluginDir + "/install.sh", "--quiet"]
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message.length > 0)
          root.lastError = message.length > 400 ? message.slice(-400) : message
      }
    }
    onExited: function (exitCode) {
      if (exitCode === 0)
        return
      console.warn("chroma: installer exited " + exitCode
                   + (root.lastError.length > 0 ? ": " + root.lastError : ""))
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: false
    onTriggered: {
      if (!installer.running)
        installer.running = true
    }
  }
}
