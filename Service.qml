import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property string homeDir: Quickshell.env("HOME") || ""

  property bool opencodeInstalled: false
  property string opencodeVersion: ""

  property string configPath: ""
  property bool configExists: false
  property bool configHasPassword: false
  property int configPort: 49374

  property bool localReachable: false
  property string localUrl: ""
  property string localServeUrl: ""
  property string localError: ""
  property var localSessions: []
  property var localHistory: []
  property int localTotal: 0

  property bool tailscaleInstalled: false
  property bool tailscaleRunning: false
  property string selfName: ""
  property var selfIps: []
  property var peers: []

  property var pairingInbox: []

  property string selectedPeer: ""
  property string selectedSession: ""

  property bool refreshing: false
  property string actionStatus: ""
  property string lastError: ""

  readonly property int totalSessions: countSessions()
  readonly property int reachableHosts: countReachable()
  readonly property bool configured: opencodeInstalled && (localReachable || countReachable() > 0)
  readonly property bool busy: statusProcess.running || actionProcess.running
  readonly property string helperPath: String(Qt.resolvedUrl("opencode_remote_status.py")).replace("file://", "")
  readonly property string connectPath: String(Qt.resolvedUrl("opencode-remote-connect")).replace("file://", "")
  readonly property string pairPath: String(Qt.resolvedUrl("opencode-remote-pair")).replace("file://", "")

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 60, 10, 3600)

  property string _statusOutput: ""
  property string _statusError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _actionLabel: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function countSessions() {
    var count = localSessions.length
    for (var i = 0; i < peers.length; i++) {
      if (peers[i] && peers[i].sessions) count += peers[i].sessions.length
    }
    return count
  }

  function countReachable() {
    var count = localReachable ? 1 : 0
    for (var i = 0; i < peers.length; i++) {
      if (peers[i] && peers[i].reachable === true) count += 1
    }
    return count
  }

  function refresh() {
    if (statusProcess.running) return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    statusProcess.command = ["python3", helperPath]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      lastError = parsed.lastError || "Failed to read opencode status"
      return
    }
    opencodeInstalled = parsed.opencode.installed
    opencodeVersion = parsed.opencode.version
    configPath = parsed.config.path
    configExists = parsed.config.exists
    configHasPassword = parsed.config.hasPassword
    configPort = parsed.config.port
    localReachable = parsed.local.reachable
    localUrl = parsed.local.url
    localServeUrl = parsed.local.serveUrl
    localError = parsed.local.error
    localSessions = parsed.local.sessions
    localHistory = parsed.local.history
    localTotal = parsed.local.total
    tailscaleInstalled = parsed.tailscale.installed
    tailscaleRunning = parsed.tailscale.running
    selfName = parsed.tailscale.selfName
    selfIps = parsed.tailscale.selfIps
    peers = parsed.tailscale.peers
    pairingInbox = parsed.pairing.inbox
    if (parsed.lastError !== "" && !parsed.opencode.installed) {
      lastError = Model.elideStatus(parsed.lastError)
    } else if (parsed.lastError === "") {
      lastError = ""
    }
  }

  function elideStatus(text) {
    return Model.elideStatus(text)
  }

  function peerByName(name) {
    for (var i = 0; i < peers.length; i++) {
      if (peers[i] && String(peers[i].hostName || "") === String(name)) return peers[i]
    }
    return null
  }

  function selectSession(peerName, sessionId) {
    selectedPeer = String(peerName || "")
    selectedSession = String(sessionId || "")
  }

  // Launchers, not tracked operations: they must not flip `busy` and carry
  // no status. The password never appears here — opencode-remote-connect
  // reads it from the 0600 config file itself.
  // Shareable URL + phone QR. serveUrl is the tailscale-serve HTTPS URL
  // when configured, otherwise the direct server URL.
  readonly property string shareUrl: localServeUrl !== "" ? localServeUrl : localUrl

  function copyShareUrl() {
    if (shareUrl === "") {
      lastError = "No server URL yet — expose this machine first"
      return
    }
    runAction("URL copied", ["wl-copy", shareUrl])
  }

  function showPhoneQr() {
    if (shareUrl === "") {
      lastError = "No server URL yet — expose this machine first"
      return
    }
    selectSession("", "")
    launcherProcess.command = ["omarchy-launch-terminal", "sh", "-c", "opencode pair --url '" + shareUrl + "'; printf '\\nPress Enter to close '; read _"]
    launcherProcess.running = true
  }

  function openLocalSession(sessionId) {
    selectSession("", sessionId)
    var command = ["omarchy-launch-terminal", "opencode"]
    if (String(sessionId || "") !== "") command.push("--session", String(sessionId))
    launcherProcess.command = command
    launcherProcess.running = true
  }

  function openRemoteSession(peerName, sessionId) {
    var peer = peerByName(peerName)
    if (peer === null || peer.reachable !== true) {
      lastError = "That machine is not reachable right now"
      return
    }
    selectSession(peerName, sessionId)
    var target = String(sessionId || "") !== "" ? String(sessionId) : "-"
    launcherProcess.command = ["omarchy-launch-terminal", connectPath, String(peerName), target]
    launcherProcess.running = true
  }

  function openSession(peerName, sessionId) {
    if (String(peerName || "") === "") openLocalSession(sessionId)
    else openRemoteSession(peerName, sessionId)
  }

  function openConfig() {
    if (configPath === "") return
    editorProcess.command = ["omarchy-launch-editor", configPath]
    editorProcess.running = true
  }

  // Pairing operations change server state, so unlike the launchers above
  // they are tracked: busy while running, status afterwards, refresh after.
  function runAction(label, command) {
    if (actionProcess.running || !command || command.length === 0) return
    _actionLabel = label
    _actionOutput = ""
    _actionError = ""
    actionStatus = label
    actionProcess.command = command
    actionProcess.running = true
  }

  function pairWith(peerName) {
    var name = String(peerName || "").trim()
    if (name === "") {
      lastError = "Pick an online Tailscale machine first"
      return
    }
    runAction("Exposing on tailnet", [pairPath, "send", name])
  }

  function trustPairing(file, host) {
    var path = String(file || "")
    if (path === "") return
    runAction("Trusting " + String(host || "peer"), [pairPath, "trust", path])
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 1000
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: actionStatusTimer
    interval: 2600
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.applyStatus(stdout)
      else root.lastError = Model.elideStatus(stderr || stdout || "Could not read opencode status")
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || root._actionOutput || "")
      var stderr = String(actionStderr.text || root._actionError || "")
      if (exitCode !== 0) {
        root.lastError = Model.elideStatus(stderr || stdout || (root._actionLabel + " failed"))
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = String(stdout || "").split("\n")[0]
        actionStatusTimer.restart()
      }
      root._actionLabel = ""
      delayedRefresh.restart()
    }
  }

  // Fire-and-forget launchers. omarchy-launch-terminal/editor detach their
  // children, so these exit almost immediately. Output is collected only to
  // keep it off the shell's own stdout.
  Process {
    id: launcherProcess
    running: false
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  Process {
    id: editorProcess
    running: false
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }
}
