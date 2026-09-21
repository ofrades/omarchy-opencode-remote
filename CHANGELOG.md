# Changelog

## Unreleased

- Remote access now establishes a persistent OpenCode password before exposing
  the service, with compatibility for both current and newer OpenCode V2 CLIs.
- Added clear remote-login instructions, username display, password copy, and
  an explicit 30-second password reveal for signing in from another device.
- Added confirmed password rotation and clearer login guidance for discovered
  remote machines.

## 0.6.0

- Reframed the plugin as a local OpenCode publisher. Each machine now manages
  only its own service and Tailscale Serve mapping.
- Removed Taildrop pairing, peer credential storage, remote TUI launching, and
  cross-machine polling.
- On first refresh, removes legacy pairing credentials from plugin config and
  recognized `opencode-pair-*.json` files from Downloads.
- Active sessions now open in the published OpenCode web UI.
- Restored read-only discovery of OpenCode servers published by online
  Tailscale peers, with browser navigation and no credential exchange.
- Simplified the local panel to one primary browser action by removing URL
  copy and login QR controls.

## 0.5.0

- Tailnet URLs are the design: expose maps each server to
  `https://<host>.<tailnet>.ts.net/` via `tailscale serve`, and the
  helper probes that URL first (raw tailnet IP as fallback). Passwords are
  opencode-managed and stable — the plugin never generates or clears them,
  only shares them via Trust and the phone QR (`opencode pair --url`).
  Taildrop targets resolve via MagicDNS/IP, so HostNames with spaces work.
  This-machine tab shows the shareable URL with Copy and Show-QR actions.

## 0.4.0

- This-machine tab splits into **Running** (expanded) and
  **Stopped (N)** (collapsed, click to continue a past session).

## 0.3.0

- Two view pills instead of one list: **This machine** (open sessions
  only) and **Remote** (every tailnet machine grouped by state).

## 0.2.0

- One-click Taildrop pairing: *Pair with X* exposes the server and sends
  the credential, *Trust* on the other side stores it. Per-peer
  credentials, secrets never touch a command line.

## 0.1.0

- Bar pill with total session count; picker grouped by machine; remote
  sessions open via `opencode --server` over Tailscale.
