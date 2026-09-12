import QtQuick
import Quickshell
import Quickshell.Io

// Chroma service: keeps GTK/Qt (and optionally /root via one-time links)
// in step with Omarchy. Generation lives in bin/chroma-apply; the
// theme-set.d hook runs it on every switch. This service is the safety net.
Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null

  // No bar widget — defaults only. Flip via env if ever needed.
  readonly property bool autoApply: true
  readonly property bool restartApps: true
  readonly property bool syncRoot: true

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/chroma"
  readonly property string themeDir: home + "/.local/state/omarchy/current/theme"
  readonly property string pluginDir: manifest && manifest.__sourceDir
    ? manifest.__sourceDir
    : home + "/.config/omarchy/plugins/io.github.alxwolfenstein97.chroma"

  property var state: null
  property bool applying: false
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

  property string lastSeenStamp: ""
  property string lastAppliedStamp: ""
  property string failedStamp: ""
  property int failCount: 0
  property string pendingStamp: ""

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.probeTheme()
  }

  Process {
    id: probeProcess
    running: false
    command: ["sh", "-c",
      'p=$(readlink -f -- "$1") || exit 0; printf "%s %s\\n" "$p" "$(stat -c %Y -- "$p/colors.toml" 2>/dev/null)"',
      "-", root.themeDir]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onProbe(text.trim())
    }
  }

  function probeTheme() {
    if (!probeProcess.running) probeProcess.running = true
  }

  function onProbe(stamp) {
    if (stamp === "") return
    var first = lastSeenStamp === ""
    lastSeenStamp = stamp
    if (applyProcess.running) return
    if (stamp === lastAppliedStamp) return
    if (stamp === failedStamp && failCount >= 3) return
    var freshInstall = state === null
    if (!autoApply && !(first && freshInstall)) {
      lastAppliedStamp = stamp
      return
    }
    applyNow(first)
  }

  Process {
    id: applyProcess
    running: false
    command: [root.pluginDir + "/bin/chroma-apply"]
    onRunningChanged: if (!running) root.applying = false
    onExited: function(exitCode, exitStatus) {
      root.applying = false
      if (exitCode === 0) {
        root.lastAppliedStamp = root.pendingStamp
        root.failedStamp = ""
        root.failCount = 0
      } else if (root.failedStamp === root.pendingStamp) {
        root.failCount++
      } else {
        root.failedStamp = root.pendingStamp
        root.failCount = 1
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.lastError = text.trim()
        if (root.lastError !== "") console.warn("chroma", root.lastError)
      }
    }
  }

  Timer {
    interval: 30000
    running: applyProcess.running
    onTriggered: applyProcess.signal(9)
  }
  Timer {
    interval: 10000
    running: probeProcess.running
    onTriggered: probeProcess.signal(9)
  }

  Process {
    id: installer
    running: false
    command: ["bash", root.pluginDir + "/install.sh", "--quiet", "--no-pkgs"]
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message.length > 0)
          root.lastError = message.length > 400 ? message.slice(-400) : message
      }
    }
  }

  Timer {
    interval: 1500
    running: true
    repeat: false
    onTriggered: {
      if (!installer.running) installer.running = true
    }
  }

  function applyNow(firstRun) {
    if (applyProcess.running) return
    var cmd = [root.pluginDir + "/bin/chroma-apply"]
    if (!restartApps || firstRun === true) cmd.push("--no-restart")
    if (!syncRoot) cmd.push("--no-root")
    pendingStamp = lastSeenStamp
    applyProcess.command = cmd
    root.applying = true
    applyProcess.running = true
  }
}
