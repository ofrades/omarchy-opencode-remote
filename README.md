# OpenCode Remote — Omarchy bar widget (opencode + Tailscale)

One picker for every opencode session on every machine in your tailnet.
The bar shows the total session count; the panel groups sessions by
machine — this machine first, then each online Tailscale peer. Clicking a
session opens it in a terminal: locally with `opencode --session`, remotely
with `opencode --server` over the tailnet.

Remote control, not sync: a remote session's tools run on that machine.

Passwords are opencode-managed and stable: the background service always
has one (opencode regenerates it on start when missing), the plugin never
changes it — it only shares it via Trust and the phone QR. WireGuard still
decides who can reach the API at all.

## How it works

- Each machine keeps its own opencode background service and session DB.
- The widget's helper (`opencode_remote_status.py`) queries the local
  service plus `GET /api/session` on every online peer, and the panel
  renders the merged picker.
- Opening a remote session shells out to `opencode-remote-connect`, which
  resolves the peer via `tailscale status --json` and execs
  `opencode --server http://<tailnet-ip>:<port> [--session <id>]`.

## Requirements

- `opencode` v2 on every machine (the background service owns sessions)
- `tailscale` on PATH, logged in on every machine
- Python 3 (for the status helper and the connect launcher)

## Setup

Design: every opencode server is paired to its own tailnet URL —
`https://<host>.<tailnet>.ts.net/` — via `tailscale serve`. The endpoint
retains opencode's password authentication; pairing transfers that existing
credential to the selected tailnet peer.
Phones and other machines just open that URL. Two ways to expose a
machine; the widget needs no manual server commands:

1. **Expose (recommended).** Open the widget → *Expose this machine*
   under any peer section. That binds the server to its tailnet address,
   restarts it, and maps `https://<this-host>.<tailnet>.ts.net/` to it
   with `tailscale serve`. The service password is left alone (opencode
   enforces it, so it stays stable).
   It also Taildrops the effective credential to that peer — on their side an
   *Incoming pairing* appears at the top. Verify the displayed host, tailnet
   IP, and credential fingerprint, then click **Trust**. Trust only accepts a
   private, current-user-owned regular file from `~/Downloads` whose claimed
   host and IP match an online peer reported by Tailscale. Your
   sessions appear there after the next refresh.
2. **Manual.** Same steps by hand:

```sh
opencode service set hostname <tailnet-ip>
opencode service set port 49374
opencode service start
tailscale serve --bg --https=443 http://<tailnet-ip>:49374
```

Widget config lives at `~/.config/omarchy-opencode-remote/config.json`
(`0600`):

```json
{
  "port": 49374
}
```

Trusting a machine adds its entry automatically (`peers.<host>` with the
effective service password and port). `chmod 600` it — launchers read it
directly so secrets never appear in process lists.

## Install

```sh
omarchy plugin add https://github.com/ofrades/omarchy-opencode-remote.git --enable
```

Then open the widget: your local sessions show immediately, and each peer
lists its sessions or a short error (`offline`, `not paired yet`,
`connection refused`, `auth failed`, …).

## Panel

Two tabs, no setup screens:

- **This machine** — running sessions, expanded. Past sessions sit in a
  collapsed *History (N)* row underneath — expand it to continue one.
  *New local session* opens a fresh TUI.
- **Remote** — incoming pairings at the top with a **Trust** button each,
  then one section per tailnet peer: its sessions, *New session on X*,
  or a **Pair with X** row when it is not paired yet.

Keys: `r` refresh · `1–2` switch tabs · `Esc` close. Right-click the bar
pill to refresh.

## Security notes

- The service always has a password (opencode enforces it) and the plugin
  never changes it — Expose only reads and shares it via Trust or the
  phone QR, so it stays stable. Still, only expose machines on a tailnet
  you control, and never bind `0.0.0.0` on a machine whose LAN you don't
  trust (the tailnet path is WireGuard-encrypted; the LAN path is not).

## Tests

```sh
./tests/run
```
