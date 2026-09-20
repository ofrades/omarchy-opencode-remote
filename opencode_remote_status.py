#!/usr/bin/env python3
"""Single-shot status helper for the omarchy-opencode-remote bar widget.

Queries the local opencode background service plus every online Tailscale
peer exposing an opencode server, then prints one JSON document for QML.

Each server machine must expose its service inside the tailnet and share
one password (see README):

    opencode service set hostname 0.0.0.0
    opencode service set password "<shared-secret>"
    opencode service start

The shared secret lives in ~/.config/omarchy-opencode-remote/config.json
(next to an optional port override). The local machine is queried through
its own service.json, so it works even before the shared secret is set.

Never fails hard: every probe has a timeout and any failure is reported
inside the payload so the panel can show it instead of going blank.
"""

import base64
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

CONFIG_DIR_NAME = "omarchy-opencode-remote"
CONFIG_FILE_NAME = "config.json"
PAIR_APP_TAG = "omarchy-opencode-remote-pair"
PAIR_GLOB = "opencode-pair-*.json"
DEFAULT_PORT = 49374
DEFAULT_TIMEOUT_SEC = 3
MAX_SESSIONS_PER_HOST = 100


def config_home():
    override = os.environ.get("XDG_CONFIG_HOME", "").strip()
    if override:
        return override
    return os.path.join(os.path.expanduser("~"), ".config")


def load_config():
    path = os.path.join(config_home(), CONFIG_DIR_NAME, CONFIG_FILE_NAME)
    config = {"password": "", "port": DEFAULT_PORT, "timeoutSec": DEFAULT_TIMEOUT_SEC,
              "peers": {}}
    exists = os.path.isfile(path)
    if exists:
        try:
            with open(path, "r", encoding="utf-8") as handle:
                raw = json.load(handle)
        except (OSError, ValueError):
            raw = None
        if isinstance(raw, dict):
            if isinstance(raw.get("password"), str):
                config["password"] = raw["password"]
            try:
                port = int(raw.get("port", DEFAULT_PORT))
            except (TypeError, ValueError):
                port = DEFAULT_PORT
            if 1 <= port <= 65535:
                config["port"] = port
            try:
                timeout = int(raw.get("timeoutSec", DEFAULT_TIMEOUT_SEC))
            except (TypeError, ValueError):
                timeout = DEFAULT_TIMEOUT_SEC
            config["timeoutSec"] = max(1, min(15, timeout))
            peers = raw.get("peers", {}) or {}
            if isinstance(peers, dict):
                for name, entry in peers.items():
                    if not isinstance(entry, dict):
                        continue
                    password = entry.get("password", "")
                    if not isinstance(password, str):
                        continue
                    try:
                        peer_port = int(entry.get("port", config["port"]))
                    except (TypeError, ValueError):
                        peer_port = config["port"]
                    if not 1 <= peer_port <= 65535:
                        peer_port = config["port"]
                    config["peers"][str(name)] = {"password": password, "port": peer_port}
    return path, exists, config


def peer_credentials(config, host_name):
    """Per-peer credential, else the shared global one. Empty means no auth."""
    entry = config["peers"].get(host_name, {})
    if isinstance(entry, dict) and "password" in entry:
        password = entry.get("password", "")
        if not isinstance(password, str):
            password = ""
        try:
            port = int(entry.get("port", config["port"]))
        except (TypeError, ValueError):
            port = config["port"]
        if not 1 <= port <= 65535:
            port = config["port"]
        return password, port
    return config["password"], config["port"]


def command_output(command, timeout):
    try:
        completed = subprocess.run(
            command, check=False, capture_output=True, text=True, timeout=timeout
        )
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""
    return completed.returncode, (completed.stdout or "").strip()


def service_status_url(opencode_bin):
    """Parse `opencode service status` for the local server URL."""
    exit_code, out = command_output([opencode_bin, "service", "status"], 8)
    if exit_code != 0 or not out:
        return ""
    match = re.search(r"https?://[^\s/]+(?::\d+)?", out)
    return match.group(0) if match else ""


def local_password():
    path = os.path.join(config_home(), "opencode", "service.json")
    try:
        with open(path, "r", encoding="utf-8") as handle:
            raw = json.load(handle)
    except (OSError, ValueError):
        return ""
    if isinstance(raw, dict) and isinstance(raw.get("password"), str):
        return raw["password"]
    return ""


def fetch_json(url, password, timeout):
    """GET url, return (True, parsed) or (False, short error string)."""
    request = urllib.request.Request(url, method="GET")
    if password:
        token = base64.b64encode(("opencode:" + password).encode("utf-8")).decode("ascii")
        request.add_header("Authorization", "Basic " + token)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            return False, "auth failed"
        return False, "http %d" % exc.code
    except urllib.error.URLError as exc:
        reason = exc.reason
        name = type(reason).__name__ if reason is not None else ""
        text = str(reason) if reason is not None else ""
        if "Connection refused" in text or "Connect call failed" in text:
            return False, "connection refused"
        if "Timeout" in name or "timed out" in text:
            return False, "unreachable"
        if "No route to host" in text or "Name or service not known" in text:
            return False, "unreachable"
        return False, "unreachable"
    except (TimeoutError, OSError):
        return False, "unreachable"
    try:
        return True, json.loads(body)
    except ValueError:
        return False, "not an opencode server"


def epoch_ms_to_iso(value):
    try:
        stamp = float(value) / 1000.0
    except (TypeError, ValueError):
        return ""
    if stamp <= 0:
        return ""
    return datetime.fromtimestamp(stamp, tz=timezone.utc).isoformat()


def normalize_session(entry):
    if not isinstance(entry, dict):
        return None
    session_id = entry.get("id", "")
    if not session_id:
        return None
    location = entry.get("location", {}) or {}
    model = entry.get("model", {}) or {}
    provider = str(model.get("providerID", "") or "")
    model_id = str(model.get("id", "") or "")
    times = entry.get("time", {}) or {}
    updated = times.get("updated") or times.get("created")
    return {
        "id": str(session_id),
        "title": str(entry.get("title", "") or "Untitled session"),
        "directory": str(location.get("directory", "") or ""),
        "agent": str(entry.get("agent", "") or ""),
        "model": (provider + "/" + model_id).strip("/"),
        "updatedAt": epoch_ms_to_iso(updated),
    }


def list_sessions(base_url, password, timeout, only_active=False):
    ok, data = fetch_json(base_url.rstrip("/") + "/api/session", password, timeout)
    if not ok:
        return False, data, [], [], 0
    items = data.get("data", []) if isinstance(data, dict) else []
    if not isinstance(items, list):
        items = []
    total = len(items)
    active_ids = None
    if only_active:
        active_ok, active_data = fetch_json(
            base_url.rstrip("/") + "/api/session/active", password, timeout
        )
        if not active_ok:
            return False, active_data, [], [], total
        active_ids = set()
        if isinstance(active_data, dict):
            active_map = active_data.get("data", {}) or {}
            if isinstance(active_map, dict):
                active_ids = set(active_map.keys())
    open_sessions = []
    history = []
    for entry in items:
        normalized = normalize_session(entry)
        if normalized is None:
            continue
        if active_ids is not None and normalized["id"] not in active_ids:
            history.append(normalized)
        else:
            open_sessions.append(normalized)
    by_updated = lambda item: item["updatedAt"]
    open_sessions.sort(key=by_updated, reverse=True)
    history.sort(key=by_updated, reverse=True)
    return True, "", open_sessions[:MAX_SESSIONS_PER_HOST], history[:MAX_SESSIONS_PER_HOST], total


def tailscale_status(tailscale_bin):
    result = {"installed": tailscale_bin is not None, "running": False,
              "selfName": "", "selfDns": "", "selfIps": [], "rawPeers": []}
    if not tailscale_bin:
        return result
    exit_code, out = command_output([tailscale_bin, "status", "--json"], 8)
    if exit_code != 0 or not out:
        return result
    try:
        status = json.loads(out)
    except ValueError:
        return result
    result["running"] = status.get("BackendState") == "Running"
    yourself = status.get("Self", {}) or {}
    result["selfName"] = str(yourself.get("HostName", "") or "")
    result["selfDns"] = str(yourself.get("DNSName", "") or "").rstrip(".")
    ips = yourself.get("TailscaleIPs", []) or []
    result["selfIps"] = [str(ip) for ip in ips]
    peers = status.get("Peer", {}) or {}
    for peer in peers.values():
        if not isinstance(peer, dict):
            continue
        peer_ips = peer.get("TailscaleIPs", []) or []
        result["rawPeers"].append(
            {
                "hostName": str(peer.get("HostName", "") or "unknown"),
                "dnsName": str(peer.get("DNSName", "") or ""),
                "os": str(peer.get("OS", "") or ""),
                "online": peer.get("Online") is True,
                "ips": [str(ip) for ip in peer_ips],
            }
        )
    result["rawPeers"].sort(
        key=lambda peer: (not peer["online"], peer["hostName"].lower())
    )
    return result


def downloads_dir():
    return os.path.join(os.path.expanduser("~"), "Downloads")


def pairing_inbox():
    """Metadata for incoming pairing files. Passwords never leave this process."""
    inbox = []
    pattern = os.path.join(downloads_dir(), PAIR_GLOB)
    for path in sorted(glob.glob(pattern)):
        try:
            with open(path, "r", encoding="utf-8") as handle:
                raw = json.load(handle)
        except (OSError, ValueError):
            continue
        if not isinstance(raw, dict) or raw.get("app") != PAIR_APP_TAG:
            continue
        host = raw.get("host", "")
        tail_ip = raw.get("tailIP", "")
        password = raw.get("password", "")
        if not host or not tail_ip:
            continue
        if not isinstance(password, str):
            continue
        try:
            port = int(raw.get("port", DEFAULT_PORT))
        except (TypeError, ValueError):
            continue
        if not 1 <= port <= 65535:
            continue
        digest = (
            hashlib.sha256(password.encode("utf-8")).hexdigest()[:12]
            if password
            else "no-auth"
        )
        inbox.append(
            {
                "file": path,
                "host": str(host),
                "tailIP": str(tail_ip),
                "port": port,
                "username": str(raw.get("username", "opencode") or "opencode"),
                "created": str(raw.get("created", "") or ""),
                "fingerprint": digest,
            }
        )
    return inbox


def first_ip(ips):
    for ip in ips or []:
        if "." in str(ip):
            return str(ip)
    if ips:
        return str(ips[0])
    return ""


def payload():
    opencode_bin = shutil.which("opencode")
    tailscale_bin = shutil.which("tailscale")
    config_path, config_exists, config = load_config()

    data = {
        "ok": True,
        "opencode": {"installed": opencode_bin is not None, "version": ""},
        "config": {
            "path": config_path,
            "exists": config_exists,
            "hasPassword": config["password"] != "",
            "port": config["port"],
        },
        "local": {"reachable": False, "url": "", "serveUrl": "", "error": "", "sessions": [], "history": [], "total": 0},
        "tailscale": {
            "installed": tailscale_bin is not None,
            "running": False,
            "selfName": "",
            "selfIps": [],
            "peers": [],
        },
        "pairing": {"inbox": pairing_inbox()},
        "lastError": "",
    }

    if opencode_bin:
        exit_code, out = command_output([opencode_bin, "--version"], 5)
        if exit_code == 0 and out:
            data["opencode"]["version"] = out.splitlines()[0]

        url = service_status_url(opencode_bin)
        if url:
            password = local_password()
            ok, error, sessions, history, total = list_sessions(
                url, password, config["timeoutSec"], only_active=True
            )
            data["local"]["url"] = url
            data["local"]["reachable"] = ok
            data["local"]["error"] = error
            data["local"]["sessions"] = sessions
            data["local"]["history"] = history
            data["local"]["total"] = total
        else:
            data["local"]["error"] = "background service not running"
    else:
        data["lastError"] = "opencode is not installed"

    tail = tailscale_status(tailscale_bin)
    data["tailscale"]["running"] = tail["running"]
    data["tailscale"]["selfName"] = tail["selfName"]
    data["tailscale"]["selfIps"] = tail["selfIps"]
    if tail["selfDns"]:
        _serve_code, _serve_out = command_output([tailscale_bin, "serve", "status"], 8) if tailscale_bin else (1, "")
        if _serve_code == 0 and "No serve config" not in _serve_out:
            data["local"]["serveUrl"] = "https://%s/" % tail["selfDns"]

    for peer in tail["rawPeers"]:
        entry = dict(peer)
        entry["reachable"] = False
        entry["url"] = ""
        entry["error"] = ""
        entry["sessions"] = []
        if not peer["online"]:
            entry["error"] = "offline"
        elif not opencode_bin:
            entry["error"] = "opencode is not installed"
        else:
            password, port = peer_credentials(config, peer["hostName"])
            ip = first_ip(peer["ips"])
            dns = str(peer.get("dnsName", "") or "").rstrip(".")
            # Each server is paired to its tailnet URL via `tailscale serve`,
            # so prefer https://<host>.<tailnet>.ts.net/ and fall back to
            # the raw tailnet IP for machines without serve configured.
            candidates = []
            if dns:
                candidates.append("https://%s" % dns)
            if ip:
                candidates.append("http://%s:%d" % (ip, port))
            if not candidates:
                entry["error"] = "no tailscale address"
            else:
                ok, error, sessions = False, "", []
                for url in candidates:
                    entry["url"] = url
                    ok, error, sessions, _history, _total = list_sessions(
                        url, password, config["timeoutSec"]
                    )
                    if ok:
                        break
                entry["reachable"] = ok
                entry["error"] = error
                entry["sessions"] = sessions
        data["tailscale"]["peers"].append(entry)

    return data


def main():
    print(json.dumps(payload()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
