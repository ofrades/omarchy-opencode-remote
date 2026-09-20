import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root
  property var settings: ({})
  property bool opencodeInstalled: false
  property string opencodeVersion: ""
  property bool localReachable: false
  property string localUrl: ""
  property string localError: ""
  property var localSessions: []
  property var localHistory: []
  property int localTotal: 0
  property bool tailscaleInstalled: false
  property bool tailscaleRunning: false
  property string selfName: ""
  property var selfIps: []
  property var peers: []
  property bool published: false
  property string publicUrl: ""
  property bool refreshing: false
  property string actionStatus: ""
  property string lastError: ""

  readonly property bool configured: opencodeInstalled && localReachable && tailscaleRunning && published
  readonly property bool busy: statusProcess.running || actionProcess.running
  readonly property string helperPath: String(Qt.resolvedUrl("opencode_remote_status.py")).replace("file://", "")
  readonly property string publishPath: String(Qt.resolvedUrl("opencode-remote-publish")).replace("file://", "")
  readonly property int refreshIntervalSec: Math.max(10, Math.min(3600, parseInt(String(settings.refreshIntervalSec || 60), 10) || 60))

  function refresh() {
    if (statusProcess.running) return
    refreshing = true
    statusProcess.command = ["python3", helperPath]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) { lastError = parsed.lastError; return }
    opencodeInstalled = parsed.opencode.installed
    opencodeVersion = parsed.opencode.version
    localReachable = parsed.local.reachable
    localUrl = parsed.local.url
    localError = parsed.local.error
    localSessions = parsed.local.sessions
    localHistory = parsed.local.history
    localTotal = parsed.local.total
    tailscaleInstalled = parsed.tailscale.installed
    tailscaleRunning = parsed.tailscale.running
    selfName = parsed.tailscale.selfName
    selfIps = parsed.tailscale.selfIps
    peers = parsed.tailscale.peers
    published = parsed.publication.published
    publicUrl = parsed.publication.url
    lastError = parsed.lastError
  }

  function publish() {
    if (busy) return
    actionStatus = "Publishing OpenCode…"
    lastError = ""
    actionProcess.command = [publishPath]
    actionProcess.running = true
  }

  function openUrl(url) {
    var value = String(url || "")
    if (value === "") return
    Quickshell.execDetached(["omarchy-launch-browser", value])
  }

  function openDashboard() { openUrl(publicUrl) }
  function openPeer(peer) { openUrl(peer && peer.url ? peer.url : "") }
  function openSession(session) { openUrl(session && session.webUrl ? session.webUrl : publicUrl) }

  function copyUrl() {
    if (publicUrl === "") return
    actionStatus = "URL copied"
    copyProcess.command = ["wl-copy", publicUrl]
    copyProcess.running = true
  }

  function showQr() {
    if (publicUrl === "") return
    Quickshell.execDetached(["omarchy-launch-terminal", "sh", "-c", "opencode pair --url '" + publicUrl + "'; printf '\\nPress Enter to close '; read _"])
  }

  Timer { interval: root.refreshIntervalSec * 1000; repeat: true; running: true; triggeredOnStart: true; onTriggered: root.refresh() }
  Timer { id: delayedRefresh; interval: 1000; repeat: false; onTriggered: root.refresh() }
  Timer { id: statusTimer; interval: 2600; repeat: false; onTriggered: root.actionStatus = "" }

  Process {
    id: statusProcess
    property string output: ""
    command: []
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: statusProcess.output = text }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      root.refreshing = false
      if (code === 0) root.applyStatus(output)
      else root.lastError = "Could not read OpenCode status"
    }
  }

  Process {
    id: actionProcess
    property string output: ""
    property string errorOutput: ""
    command: []
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: actionProcess.output = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: actionProcess.errorOutput = text }
    onExited: function(code) {
      if (code === 0) { root.actionStatus = String(output || "Published").trim(); root.lastError = "" }
      else { root.actionStatus = ""; root.lastError = Model.elideStatus(errorOutput || output || "Publishing failed") }
      statusTimer.restart()
      delayedRefresh.restart()
    }
  }

  Process {
    id: copyProcess
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }
}
