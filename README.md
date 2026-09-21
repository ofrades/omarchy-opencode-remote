# OpenCode Remote — Omarchy publisher

Publish this machine's OpenCode server securely through Tailscale and open it
from any device on your tailnet.

Every machine publishes itself. The plugin discovers published OpenCode
servers on online Tailscale peers, but never exchanges credentials or
configures those peers.

## How it works

- OpenCode keeps its own background service and password authentication. The
  plugin creates one persistent strong password when needed, so it does not
  change when the server restarts.
- **Publish this machine** binds that service to the machine's Tailscale IP,
  starts it, and maps `https://<host>.<tailnet>.ts.net/` with
  `tailscale serve`.
- The panel shows local service health and active sessions. Clicking a session
  opens its current OpenCode web route; the dashboard action opens the server
  root.
- The Remote view probes online peers' MagicDNS URLs and opens detected
  OpenCode servers in the browser. Password-protected servers are shown as
  **Login required**; remote session counts are unavailable without storing
  their credentials.
- Other devices open the tailnet URL and log in normally. OpenCode owns the
  credential and login flow.

`tailscale serve --bg` persists its publication configuration. Availability
still depends on Tailscale and the OpenCode background service running.

## Requirements

- OpenCode v2
- Tailscale, connected with MagicDNS enabled
- Python 3

## Install

```sh
omarchy plugin add https://github.com/ofrades/omarchy-opencode-remote.git --enable
```

Open the widget and choose **Publish this machine**. Once healthy, use:

- **Open dashboard** to launch the web UI.
- An active or historical session row to open that session in the browser.
- **Copy login password** when the browser asks you to sign in. The username is
  `opencode`. If you are signing in on another device, choose **Show login
  password** and enter it there. It hides again after 30 seconds. Use **Change
  login password** to rotate it on this machine.

The optional port lives in
`~/.config/omarchy-opencode-remote/config.json`:

```json
{
  "port": 49374
}
```

## Security

- OpenCode password authentication remains enabled.
- The password is owned by OpenCode and persists across server restarts. The
  plugin does not keep a second copy.
- Revealing the password is an explicit local action. The panel clears it from
  memory after 30 seconds or when the panel closes.
- The plugin never copies or stores peer credentials.
- Version 0.6 removes credentials left by the old pairing feature from its
  config and recognized pairing files in `~/Downloads`.
- Tailscale controls which devices can reach the published URL.
- The service binds to the machine's Tailscale address, not `0.0.0.0`.

## Tests

```sh
./tests/run
```
