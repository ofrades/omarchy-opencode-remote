// Shared parsing and formatting for the opencode-remote plugin.
// Mirrors the structure of the omarchy-dotfiles Model.js: pure
// functions, no shell access, testable with plain node.

function defaultStatus() {
  return {
    ok: true,
    opencode: { installed: false, version: "" },
    config: { path: "", exists: false, hasPassword: false, port: 49374 },
    local: { reachable: false, url: "", error: "", sessions: [], history: [], total: 0 },
    tailscale: {
      installed: false, running: false, selfName: "", selfIps: [], peers: []
    },
    pairing: { inbox: [] },
    lastError: ""
  }
}

function normalizeSession(entry) {
  if (!entry || typeof entry !== "object") return null
  var id = String(entry.id || "")
  if (id === "") return null
  return {
    id: id,
    title: String(entry.title || "Untitled session"),
    directory: String(entry.directory || ""),
    agent: String(entry.agent || ""),
    model: String(entry.model || ""),
    updatedAt: String(entry.updatedAt || "")
  }
}

function normalizePeer(peer) {
  var base = {
    hostName: "unknown", dnsName: "", os: "", online: false, ips: [],
    reachable: false, url: "", error: "", sessions: []
  }
  if (!peer || typeof peer !== "object") return base
  base.hostName = String(peer.hostName || "unknown")
  base.dnsName = String(peer.dnsName || "")
  base.os = String(peer.os || "")
  base.online = peer.online === true
  base.reachable = peer.reachable === true
  base.url = String(peer.url || "")
  base.error = String(peer.error || "")
  if (Array.isArray(peer.ips)) base.ips = peer.ips.map(String)
  if (Array.isArray(peer.sessions)) {
    base.sessions = peer.sessions.map(normalizeSession).filter(function(item) {
      return item !== null
    })
  }
  return base
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultStatus()
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return defaultStatus()
    var base = defaultStatus()
    if (parsed.opencode && typeof parsed.opencode === "object") {
      base.opencode.installed = parsed.opencode.installed === true
      base.opencode.version = String(parsed.opencode.version || "")
    }
    if (parsed.config && typeof parsed.config === "object") {
      base.config.path = String(parsed.config.path || "")
      base.config.exists = parsed.config.exists === true
      base.config.hasPassword = parsed.config.hasPassword === true
      var port = parseInt(parsed.config.port, 10)
      if (isFinite(port) && port >= 1 && port <= 65535) base.config.port = port
    }
    if (parsed.local && typeof parsed.local === "object") {
      base.local.reachable = parsed.local.reachable === true
      base.local.url = String(parsed.local.url || "")
      base.local.error = String(parsed.local.error || "")
      base.local.total = parseInt(parsed.local.total, 10) || 0
      if (Array.isArray(parsed.local.sessions)) {
        base.local.sessions = parsed.local.sessions.map(normalizeSession).filter(function(item) {
          return item !== null
        })
      }
      if (Array.isArray(parsed.local.history)) {
        base.local.history = parsed.local.history.map(normalizeSession).filter(function(item) {
          return item !== null
        })
      }
    }
    if (parsed.tailscale && typeof parsed.tailscale === "object") {
      var tail = parsed.tailscale
      base.tailscale.installed = tail.installed === true
      base.tailscale.running = tail.running === true
      base.tailscale.selfName = String(tail.selfName || "")
      if (Array.isArray(tail.selfIps)) base.tailscale.selfIps = tail.selfIps.map(String)
      if (Array.isArray(tail.peers)) base.tailscale.peers = tail.peers.map(normalizePeer)
    }
    if (parsed.pairing && typeof parsed.pairing === "object"
        && Array.isArray(parsed.pairing.inbox)) {
      base.pairing.inbox = parsed.pairing.inbox.map(function(item) {
        if (!item || typeof item !== "object") return null
        return {
          file: String(item.file || ""),
          host: String(item.host || "unknown"),
          tailIP: String(item.tailIP || ""),
          port: parseInt(item.port, 10) || 0,
          username: String(item.username || "opencode"),
          created: String(item.created || ""),
          fingerprint: String(item.fingerprint || "")
        }
      }).filter(function(item) {
        return item !== null && item.file !== "" && item.port > 0
      })
    }
    base.lastError = String(parsed.lastError || "")
    return base
  } catch (e) {
    var failed = defaultStatus()
    failed.ok = false
    failed.lastError = "Failed to parse opencode status"
    return failed
  }
}

function totalSessions(parsed) {
  var count = parsed.local.sessions.length
  for (var i = 0; i < parsed.tailscale.peers.length; i++) {
    count += parsed.tailscale.peers[i].sessions.length
  }
  return count
}

function reachableHosts(parsed) {
  var count = parsed.local.reachable ? 1 : 0
  for (var i = 0; i < parsed.tailscale.peers.length; i++) {
    if (parsed.tailscale.peers[i].reachable) count += 1
  }
  return count
}

function sessionSubtitle(session) {
  var parts = []
  if (session.directory !== "") parts.push(session.directory)
  if (session.model !== "") parts.push(session.model)
  var when = relativeTime(session.updatedAt)
  if (when !== "") parts.push(when)
  return parts.join(" · ")
}

function shortModel(model) {
  var value = String(model || "")
  var slash = value.lastIndexOf("/")
  return slash >= 0 ? value.substring(slash + 1) : value
}

function relativeTime(isoText, nowMs) {
  var stamp = Date.parse(String(isoText || ""))
  if (isNaN(stamp)) return ""
  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  var diff = Math.max(0, Math.floor((now - stamp) / 1000))
  if (diff < 60) return "Just now"
  var minutes = Math.floor(diff / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  var months = Math.floor(days / 30)
  if (months < 12) return months + "mo ago"
  return Math.floor(days / 365) + "y ago"
}

function peerLabel(peer) {
  if (!peer) return ""
  var name = String(peer.hostName || "unknown")
  var ips = peer.ips || []
  var detail = ips.length > 0 ? String(ips[0]) : String(peer.os || "")
  if (detail !== "") return name + " · " + detail
  return name
}

function elideStatus(text) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  return value.length > 140 ? value.substring(0, 137) + "…" : value
}

function isConfigured(parsed) {
  return parsed.opencode.installed === true
    && (parsed.local.reachable || reachableHosts(parsed) > 0)
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStatus: parseStatus,
    defaultStatus: defaultStatus,
    normalizeSession: normalizeSession,
    normalizePeer: normalizePeer,
    totalSessions: totalSessions,
    reachableHosts: reachableHosts,
    sessionSubtitle: sessionSubtitle,
    shortModel: shortModel,
    relativeTime: relativeTime,
    peerLabel: peerLabel,
    elideStatus: elideStatus,
    isConfigured: isConfigured
  }
}
