# Privacy

## Short version

This project collects nothing. There is no telemetry, no analytics, no crash
reporting, no update check, and no network call that is not the operator's own
proxy probe.

## What stays on your host

Everything. The installer writes only:

- `/etc/claude-egress-guard.conf` — proxy URL, expected exit address, country,
  allow list. Mode `0600`, root-owned.
- `/usr/local/{bin,sbin,lib}` — the gate, the checker, the CLI.
- `/opt/claude-real/claude` — a symlink to the package binary.
- `/var/lib/claude-egress-guard/backup/` — copies of whatever the installer
  replaced.

No file leaves the host. No file is uploaded by any component. The backslash
backup directory can contain a proxy URL with credentials if your proxy endpoint
embeds them — treat it as sensitive and remove it with `uninstall` when done.

## Network calls

The only outbound requests are made **by the host, through the proxy you
configure**, and only to the endpoints in your config:

- `TRACE_URL` — default `https://www.cloudflare.com/cdn-cgi/trace`, a generic
  CDN edge trace used to read the public exit address. It does not reach any AI
  provider.
- `FALLBACK_URL` — default `https://ipinfo.io/json`, used only when the trace
  endpoint fails.

Both are plain GETs. They send no identifiers, no account data, and no request
bodies. You can point them at any equivalent endpoint.

`claude-egress-guard verify --deep` additionally requests `https://example.com/`
twice: once directly (it must fail, which proves the jail blocks egress) and once
through the proxy (it must succeed). Both requests are made by the host you run
it on, carry no identifiers, and go to a reserved documentation hostname.

## This repository and CI

- The repository contains no operator data. Examples use documentation address
  space (RFC 5737) and `example.com`.
- CI runs shellcheck, the sandboxed self-test and a leak scan. It has no access
  to any deployment and holds no secrets beyond the default `GITHUB_TOKEN` with
  read-only permissions.

## Filing an issue

Redact before posting:

- public IP addresses (replace with `203.0.113.x`),
- proxy URLs and credentials,
- hostnames and account identifiers,
- full config files.

Paste the `verify` summary and the failing line only.
