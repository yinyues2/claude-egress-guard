# claude-egress-guard

**A fail-closed egress gate for Claude Code on Linux hosts — packaged as an agent skill.**

Claude Code on a VPS is easy to set up and easy to leak. A shell alias or a
`claude()` function only covers interactive shells: Python, `sh -c`, cron,
systemd units and anything calling `/usr/bin/claude` walk straight past it, and
a proxy that dies mid-session silently turns into a direct connection from the
datacenter IP.

This project pins every Claude Code invocation to one proxy and one expected
exit address, refuses to start when that path is not available, and optionally
jails the whole process tree at the kernel level so child processes cannot
reach the public internet even if they ignore proxy variables.

```
claude  (any entry point)
  └─ /usr/local/bin/claude           gate: egress check -> proxy env -> jail
       ├─ /usr/bin/claude            same gate (npm updates rewrite this; the gate self-heals)
       └─ /opt/claude-real/claude    real binary (symlink, follows package updates)
            └─ your proxy            127.0.0.1:1080 -> expected exit address
```

## What it guarantees

| Layer | Behaviour |
| --- | --- |
| Exit check | Before every start, the proxy is asked for its public address and country. Mismatch, timeout or HTTP error = **refuse to start** (exit 77). |
| Proxy environment | `ALL_PROXY`, `http_proxy`, `https_proxy` (upper and lower case) exported to the client and every child. |
| Kernel jail (optional, default on) | The Claude process tree runs in a transient systemd scope with `IPAddressDeny=any`; only loopback, the allow-listed networks (your proxy upstream, DNS resolvers, tailnet) stay reachable. |
| Self-heal | Package self-updates rewrite `/usr/bin/claude` back into a symlink; the gate restores itself on the next invocation. |
| Fail-closed | Missing config, missing checker, unreachable proxy, wrong exit, wrong country, unavailable `systemd-run`: all refuse. There is no "continue anyway" path. |

## What it does not do

- It does not create, configure or monitor the proxy itself. You supply an
  HTTP/mixed endpoint that already exits where you want.
- It is not a VPN and does not hide traffic from the host's other services.
  It gates Claude Code only.
- It cannot make an account safe, cannot prevent provider-side risk checks, and
  does not help with anything that violates a provider's terms. Account
  registration, payment and identity verification stay with the account owner.
- It does not rotate IPs, retry, or fall back to a direct connection.

## Requirements

- Linux with systemd 235+ (Debian 12/13, Ubuntu 22.04/24.04 tested patterns)
- `bash` 4.3+, `curl`, `install`, `readlink`
- root for a real install (`--prefix` allows a sandboxed install for tests)
- Claude Code already installed (npm-global or native installer)

## Quick start

```bash
git clone https://github.com/yinyues2/claude-egress-guard.git
cd claude-egress-guard/skills/claude-egress-guard/scripts

# 1) show the plan first
sudo ./claude-egress-guard install \
  --proxy http://127.0.0.1:1080 \
  --exit-ip 203.0.113.10 \
  --country JP \
  --dry-run

# 2) install (backs up anything it replaces)
sudo ./claude-egress-guard install \
  --proxy http://127.0.0.1:1080 \
  --exit-ip 203.0.113.10 \
  --country JP

# 3) verify, including a live jail test
sudo claude-egress-guard verify --deep
```

`203.0.113.10` is documentation address space (RFC 5737); replace it with the
address your proxy actually reports.

If your proxy upstream or a private network has to stay reachable inside the
jail, add it explicitly:

```bash
sudo claude-egress-guard install ... --allow 100.64.0.0/10,192.0.2.0/24
```

Loopback and the host's IPv4 DNS resolvers are added automatically.

## Verify and drill

```bash
sudo claude-egress-guard verify          # static checks + live egress check
sudo claude-egress-guard verify --deep   # also proves the jail blocks direct egress
sudo claude-egress-guard status          # current policy, proxy credentials masked
sudo claude-egress-guard drill --service my-proxy.service
```

`drill` stops the proxy unit, proves the gate refuses to start, restarts the
unit and waits for recovery. It refuses to touch units whose name suggests SSH,
Tailscale or Docker, and restarts the unit on exit even if it fails midway.

Exit codes: `0` success, `1` verification failed, `2` usage, `77` gate refused.

## After a package update

Claude Code's self-update replaces the package files and re-creates the
`/usr/bin/claude` symlink. The gate detects that and reinstalls itself on the
next PATH invocation. After any manual `npm i -g`, run:

```bash
sudo claude-egress-guard verify --deep
```

## Changing the expected exit

Edit `/etc/claude-egress-guard.conf` (`EXPECTED_IP`, `EXPECTED_COUNTRY`,
`ALLOW_IPS`, `STRICT_NET`) and run `verify`. The file is mode 0600 and is the
only place policy lives.

To keep the egress check but drop the kernel jail:

```bash
sudo sed -i 's/^STRICT_NET=1/STRICT_NET=0/' /etc/claude-egress-guard.conf
```

## Uninstall

```bash
sudo claude-egress-guard uninstall
```

Restores the files replaced during install from
`/var/lib/claude-egress-guard/backup/<timestamp>/` and removes the gate. Backups
are kept so a mistake is recoverable.

## Use it as an agent skill

`skills/claude-egress-guard/SKILL.md` is written for an agent (Hermes, Codex or
any skill-capable runner) and tells it how to interview the operator, install,
verify, drill and record evidence without touching anything it does not own.
The reference files hold the decision points, the authorization tiers and the
troubleshooting table.

Copy `skills/claude-egress-guard/` into your skills directory, for example:

```bash
cp -R skills/claude-egress-guard ~/.hermes/skills/       # Hermes
cp -R skills/claude-egress-guard ~/.codex/skills/       # Codex
```

## Repository layout

```
skills/claude-egress-guard/
  SKILL.md                    agent instructions
  references/                 playbook, troubleshooting
  scripts/claude-egress-guard installer / verifier / drill
  scripts/guard-claude.sh     the gate itself (installed as `claude`)
  scripts/egress-check.sh     exit checker (also runnable standalone)
  scripts/selftest.sh         sandboxed test suite (no root, no network)
  templates/                  example configuration
tools/leak-scan.py            blocks accidental secrets/PII before commit
```

## Development

```bash
bash skills/claude-egress-guard/scripts/selftest.sh
shellcheck -x -S warning skills/claude-egress-guard/scripts/*
python3 tools/leak-scan.py
```

CI runs the same checks on every push.

## License

Apache-2.0. See [LICENSE](LICENSE).

## Security and privacy

Read [SECURITY.md](SECURITY.md) for the threat model and reporting process, and
[PRIVACY.md](PRIVACY.md) for what this project does and does not collect (short
version: nothing — no telemetry, no analytics, no network calls except your own
proxy probe).
