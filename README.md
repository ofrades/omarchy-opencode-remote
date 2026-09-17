# OpenCode Remote — Omarchy bar widget (opencode + Tailscale)

One picker for every opencode session on every machine in your tailnet.
The bar shows the total session count; the panel groups sessions by
machine — this machine first, then each online Tailscale peer. Clicking a
session opens it in a terminal: locally with `opencode --session`, remotely
with `opencode --server` over the tailnet.

Remote control, not sync: a remote session's tools run on that machine.

## How it works

- Each machine keeps its own opencode background service and session DB.
- The widget's helper (`opencode_remote_status.py`) queries the local
  service plus `GET /api/session` on every online peer, and the panel
  renders the merged picker.
- Opening a remote session shells out to `opencode-remote-connect`, which
  resolves the peer via `tailscale status --json` and execs
  `opencode --server http://<tailnet-ip>:<port> --session <id>` with the
  shared password from the environment (never on a command line).

## Requirements

- `opencode` v2 on every machine (the background service owns sessions)
- `tailscale` on PATH, logged in on every machine
- Python 3 (for the status helper and the connect launcher)

## Setup

Two ways to connect machines. Pairing needs no manual server commands:

1. **Pair (recommended).** On machine A, open the widget → *Pair with B*
   under B's section. That binds A's server to its tailnet address (reusing
   the existing service password, or generating one on first use) and
   Taildrops the credential to B. On machine B, an *Incoming pairing*
   appears at the top — click **Trust**. B's sessions appear after the
   next refresh. Repeat the other way round for bidirectional access.
2. **Manual.** Set the same secret everywhere and put it in the widget
   config (see below).

```sh
opencode service set hostname 0.0.0.0
opencode service set password "<shared-secret>"
opencode service start
```

Widget config lives at `~/.config/omarchy-opencode-remote/config.json`
(`0600`):

```json
{
  "password": "<optional shared secret>",
  "port": 49374
}
```

Pairing adds one entry per trusted machine automatically:

```json
{
  "peers": {
    "desktop": { "password": "<random secret>", "port": 49374 }
  }
}
```

`chmod 600` it — both launchers read it directly so secrets never appear
in process lists. The local machine works without this file (the helper
reads its own `service.json`); unpaired remotes report "not paired yet".

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

- The shared secret is basic-auth for full opencode API access on each
  server machine: pick a long random one, keep the config `0600`, and only
  ever bind `0.0.0.0` on machines whose LAN you trust (the tailnet path is
  WireGuard-encrypted; the LAN path is not).
- Binding only the Tailscale interface is possible too
  (`opencode service set hostname <tailnet-ip>`), at the cost of redoing it
  if the IP changes.

## Tests

```sh
./tests/run
```
