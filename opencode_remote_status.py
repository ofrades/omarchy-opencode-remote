#!/usr/bin/env python3
"""Report local OpenCode publication and session status for the bar widget."""

import base64
import glob
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

DEFAULT_TIMEOUT_SEC = 3
MAX_SESSIONS = 100
DEFAULT_PORT = 49374


def config_home():
    return os.environ.get("XDG_CONFIG_HOME", "").strip() or os.path.join(
        os.path.expanduser("~"), ".config"
    )


def migrate_legacy_config():
    """Preserve the port while deleting credentials left by pre-0.6 pairing."""
    directory = os.path.join(config_home(), "omarchy-opencode-remote")
    path = os.path.join(directory, "config.json")
    try:
        with open(path, "r", encoding="utf-8") as handle:
            raw = json.load(handle)
    except (OSError, ValueError):
        return
    if not isinstance(raw, dict) or not ({"password", "peers", "timeoutSec"} & set(raw)):
        return
    try:
        port = int(raw.get("port", DEFAULT_PORT))
    except (TypeError, ValueError):
        port = DEFAULT_PORT
    if not 1 <= port <= 65535:
        port = DEFAULT_PORT
    os.makedirs(directory, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=directory, prefix=".tmp-config-")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump({"port": port}, handle, indent=2)
            handle.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except OSError:
            pass


def remove_legacy_pairing_files():
    """Delete only credential files created by the removed pairing feature."""
    pattern = os.path.join(os.path.expanduser("~"), "Downloads", "opencode-pair-*.json")
    for path in glob.glob(pattern):
        try:
            info = os.lstat(path)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
                continue
            with open(path, "r", encoding="utf-8") as handle:
                raw = json.load(handle)
            if not isinstance(raw, dict) or raw.get("app") != "omarchy-opencode-remote-pair":
                continue
            os.unlink(path)
        except (OSError, ValueError):
            continue


def command_output(command, timeout=8):
    try:
        completed = subprocess.run(
            command, check=False, capture_output=True, text=True, timeout=timeout
        )
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""
    return completed.returncode, (completed.stdout or "").strip()


def service_status_url(opencode_bin):
    code, out = command_output([opencode_bin, "service", "status"])
    if code != 0:
        return ""
    match = re.search(r"https?://[^\s/]+(?::\d+)?", out)
    return match.group(0) if match else ""


def service_password():
    path = os.path.join(config_home(), "opencode", "service.json")
    try:
        with open(path, "r", encoding="utf-8") as handle:
            raw = json.load(handle)
    except (OSError, ValueError):
        return ""
    return raw.get("password", "") if isinstance(raw, dict) and isinstance(raw.get("password"), str) else ""


def fetch_json(url, password):
    request = urllib.request.Request(url, method="GET")
    if password:
        token = base64.b64encode(("opencode:" + password).encode()).decode("ascii")
        request.add_header("Authorization", "Basic " + token)
    try:
        with urllib.request.urlopen(request, timeout=DEFAULT_TIMEOUT_SEC) as response:
            return True, json.loads(response.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as error:
        return False, "auth failed" if error.code == 401 else "http %d" % error.code
    except (urllib.error.URLError, TimeoutError, OSError):
        return False, "unreachable"
    except ValueError:
        return False, "not an OpenCode server"


def epoch_ms_to_iso(value):
    try:
        stamp = float(value) / 1000.0
    except (TypeError, ValueError):
        return ""
    return datetime.fromtimestamp(stamp, tz=timezone.utc).isoformat() if stamp > 0 else ""


def web_session_url(public_url, session_id):
    if not public_url:
        return ""
    server = public_url.rstrip("/")
    encoded = base64.urlsafe_b64encode(server.encode()).decode().rstrip("=")
    return "%s/server/%s/session/%s" % (server, encoded, session_id)


def normalize_session(entry, public_url):
    if not isinstance(entry, dict) or not entry.get("id"):
        return None
    location = entry.get("location", {}) or {}
    model = entry.get("model", {}) or {}
    times = entry.get("time", {}) or {}
    session_id = str(entry["id"])
    return {
        "id": session_id,
        "title": str(entry.get("title", "") or "Untitled session"),
        "directory": str(location.get("directory", "") or ""),
        "agent": str(entry.get("agent", "") or ""),
        "model": (str(model.get("providerID", "") or "") + "/" + str(model.get("id", "") or "")).strip("/"),
        "updatedAt": epoch_ms_to_iso(times.get("updated") or times.get("created")),
        "webUrl": web_session_url(public_url, session_id),
    }


def list_sessions(base_url, password, public_url):
    ok, data = fetch_json(base_url.rstrip("/") + "/api/session", password)
    if not ok:
        return False, data, [], [], 0
    items = data.get("data", []) if isinstance(data, dict) else []
    items = items if isinstance(items, list) else []
    active_ok, active_data = fetch_json(base_url.rstrip("/") + "/api/session/active", password)
    if not active_ok:
        return False, active_data, [], [], len(items)
    active_map = active_data.get("data", {}) if active_ok and isinstance(active_data, dict) else {}
    active_ids = set(active_map.keys()) if isinstance(active_map, dict) else set()
    browser_url = public_url or base_url
    sessions = [normalize_session(item, browser_url) for item in items]
    sessions = [item for item in sessions if item is not None]
    sessions.sort(key=lambda item: item["updatedAt"], reverse=True)
    active = [item for item in sessions if item["id"] in active_ids]
    history = [item for item in sessions if item["id"] not in active_ids]
    return True, "", active[:MAX_SESSIONS], history[:MAX_SESSIONS], len(items)


def tailscale_status(tailscale_bin):
    result = {"installed": bool(tailscale_bin), "running": False, "selfName": "", "selfDns": "", "selfIps": [], "peers": []}
    if not tailscale_bin:
        return result
    code, out = command_output([tailscale_bin, "status", "--json"])
    if code != 0 or not out:
        return result
    try:
        status = json.loads(out)
    except ValueError:
        return result
    own = status.get("Self", {}) or {}
    result.update({
        "running": status.get("BackendState") == "Running",
        "selfName": str(own.get("HostName", "") or ""),
        "selfDns": str(own.get("DNSName", "") or "").rstrip("."),
        "selfIps": [str(value) for value in (own.get("TailscaleIPs", []) or [])],
    })
    for peer in (status.get("Peer", {}) or {}).values():
        if not isinstance(peer, dict):
            continue
        result["peers"].append({
            "hostName": str(peer.get("HostName", "") or "unknown"),
            "dnsName": str(peer.get("DNSName", "") or "").rstrip("."),
            "online": peer.get("Online") is True,
        })
    return result


def probe_peer(peer):
    result = dict(peer)
    result.update({"detected": False, "url": "", "loginRequired": False, "error": ""})
    if not peer["online"]:
        result["error"] = "offline"
        return result
    if not peer["dnsName"]:
        result["error"] = "no MagicDNS name"
        return result
    base_url = "https://%s" % peer["dnsName"]
    request = urllib.request.Request(base_url + "/api/info", method="GET")
    try:
        with urllib.request.urlopen(request, timeout=DEFAULT_TIMEOUT_SEC) as response:
            body = json.loads(response.read().decode("utf-8", "replace"))
            if response.status == 200 and isinstance(body, dict):
                result.update({"detected": True, "url": base_url + "/"})
            else:
                result["error"] = "not OpenCode"
    except urllib.error.HTTPError as error:
        realm = str(error.headers.get("WWW-Authenticate", ""))
        if error.code == 401 and 'Basic realm="Secure Area"' in realm:
            result.update({"detected": True, "url": base_url + "/", "loginRequired": True})
        else:
            result["error"] = "http %d" % error.code
    except (urllib.error.URLError, TimeoutError, OSError):
        result["error"] = "not published"
    except ValueError:
        result["error"] = "not OpenCode"
    return result


def discover_peers(peers):
    if not peers:
        return []
    with ThreadPoolExecutor(max_workers=min(8, len(peers))) as pool:
        results = list(pool.map(probe_peer, peers))
    return sorted(results, key=lambda peer: (not peer["detected"], not peer["online"], peer["hostName"].lower()))


def publication_url(tailscale_bin, tail, local_url):
    if not tailscale_bin or not tail["running"] or not tail["selfDns"] or not local_url:
        return ""
    code, out = command_output([tailscale_bin, "serve", "status"])
    if code != 0 or not out or "No serve config" in out or local_url not in out:
        return ""
    return "https://%s/" % tail["selfDns"]


def payload():
    migrate_legacy_config()
    remove_legacy_pairing_files()
    opencode_bin = shutil.which("opencode")
    tailscale_bin = shutil.which("tailscale")
    tail = tailscale_status(tailscale_bin)
    local_url = service_status_url(opencode_bin) if opencode_bin else ""
    public_url = publication_url(tailscale_bin, tail, local_url)
    data = {
        "ok": True,
        "opencode": {"installed": bool(opencode_bin), "version": ""},
        "local": {"reachable": False, "url": "", "error": "", "sessions": [], "history": [], "total": 0},
        "tailscale": {
            **{key: tail[key] for key in ("installed", "running", "selfName", "selfIps")},
            "peers": discover_peers(tail["peers"]) if tail["running"] else [],
        },
        "publication": {"published": bool(public_url), "url": public_url},
        "lastError": "",
    }
    if not opencode_bin:
        data["lastError"] = "opencode is not installed"
        return data
    code, version = command_output([opencode_bin, "--version"], 5)
    if code == 0:
        data["opencode"]["version"] = version.splitlines()[0] if version else ""
    data["local"]["url"] = local_url
    if not local_url:
        data["local"]["error"] = "background service not running"
        return data
    ok, error, sessions, history, total = list_sessions(local_url, service_password(), public_url)
    data["local"].update({"reachable": ok, "error": error, "sessions": sessions, "history": history, "total": total})
    return data


if __name__ == "__main__":
    print(json.dumps(payload()))
    sys.exit(0)
