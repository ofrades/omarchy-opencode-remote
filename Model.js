function defaultStatus() {
  return {
    ok: true,
    opencode: { installed: false, version: "" },
    local: { reachable: false, url: "", error: "", sessions: [], history: [], total: 0 },
    tailscale: { installed: false, running: false, selfName: "", selfIps: [], peers: [] },
    publication: { published: false, url: "" },
    lastError: ""
  }
}

function normalizeSession(entry) {
  if (!entry || typeof entry !== "object" || !entry.id) return null
  return {
    id: String(entry.id),
    title: String(entry.title || "Untitled session"),
    directory: String(entry.directory || ""),
    agent: String(entry.agent || ""),
    model: String(entry.model || ""),
    updatedAt: String(entry.updatedAt || ""),
    webUrl: String(entry.webUrl || "")
  }
}

function normalizePeer(entry) {
  if (!entry || typeof entry !== "object") return null
  return {
    hostName: String(entry.hostName || "unknown"),
    dnsName: String(entry.dnsName || ""),
    online: entry.online === true,
    detected: entry.detected === true,
    loginRequired: entry.loginRequired === true,
    url: String(entry.url || ""),
    error: String(entry.error || "")
  }
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultStatus()
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return defaultStatus()
    var result = defaultStatus()
    if (parsed.opencode) {
      result.opencode.installed = parsed.opencode.installed === true
      result.opencode.version = String(parsed.opencode.version || "")
    }
    if (parsed.local) {
      result.local.reachable = parsed.local.reachable === true
      result.local.url = String(parsed.local.url || "")
      result.local.error = String(parsed.local.error || "")
      result.local.total = parseInt(parsed.local.total, 10) || 0
      if (Array.isArray(parsed.local.sessions)) result.local.sessions = parsed.local.sessions.map(normalizeSession).filter(Boolean)
      if (Array.isArray(parsed.local.history)) result.local.history = parsed.local.history.map(normalizeSession).filter(Boolean)
    }
    if (parsed.tailscale) {
      result.tailscale.installed = parsed.tailscale.installed === true
      result.tailscale.running = parsed.tailscale.running === true
      result.tailscale.selfName = String(parsed.tailscale.selfName || "")
      if (Array.isArray(parsed.tailscale.selfIps)) result.tailscale.selfIps = parsed.tailscale.selfIps.map(String)
      if (Array.isArray(parsed.tailscale.peers)) result.tailscale.peers = parsed.tailscale.peers.map(normalizePeer).filter(Boolean)
    }
    if (parsed.publication) {
      result.publication.published = parsed.publication.published === true
      result.publication.url = String(parsed.publication.url || "")
    }
    result.lastError = String(parsed.lastError || "")
    return result
  } catch (error) {
    var failed = defaultStatus()
    failed.ok = false
    failed.lastError = "Failed to parse OpenCode status"
    return failed
  }
}

function relativeTime(isoText, nowMs) {
  var stamp = Date.parse(String(isoText || ""))
  if (isNaN(stamp)) return ""
  var diff = Math.max(0, Math.floor(((nowMs === undefined ? Date.now() : Number(nowMs)) - stamp) / 1000))
  if (diff < 60) return "Just now"
  var minutes = Math.floor(diff / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  return days < 30 ? days + "d ago" : Math.floor(days / 30) + "mo ago"
}

function sessionSubtitle(session) {
  var parts = []
  if (session.directory) parts.push(session.directory)
  if (session.model) parts.push(session.model)
  var when = relativeTime(session.updatedAt)
  if (when) parts.push(when)
  return parts.join(" · ")
}

function elideStatus(text) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  return value.length > 140 ? value.substring(0, 137) + "…" : value
}

if (typeof module !== "undefined") module.exports = {
  defaultStatus: defaultStatus,
  normalizeSession: normalizeSession,
  normalizePeer: normalizePeer,
  parseStatus: parseStatus,
  relativeTime: relativeTime,
  sessionSubtitle: sessionSubtitle,
  elideStatus: elideStatus
}
