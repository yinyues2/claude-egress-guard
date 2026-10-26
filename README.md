# claude-egress-guard

[![ci](https://github.com/yinyues2/claude-egress-guard/actions/workflows/ci.yml/badge.svg)](https://github.com/yinyues2/claude-egress-guard/actions/workflows/ci.yml)

**A one-stop skill and installer for running Claude Code safely on a Linux host:
from a bare machine to a gated client, then keeping it that way.**

Claude Code on a VPS is easy to install and easy to leak. A shell alias or a
`claude()` function only covers interactive shells: Python, `sh -c`, cron,
systemd units and anything calling `/usr/bin/claude` walk straight past it, and a
proxy that dies mid-session silently turns into a direct connection from the
datacenter IP.

So the project is organized in four parts, with one enforcement core:

| Part | What it covers | Entry point |
| --- | --- | --- |
| **Deploy** | eligibility, host baseline, proxy proven stable, client installed but not launched, first login through the gate | `preflight`, [`zero-to-deployed.md`](skills/claude-egress-guard/references/zero-to-deployed.md) |
| **Egress** | one verified exit, proxy injection, kernel jail for the whole process tree, self-heal after updates, no fallback | `install`, `verify --deep`, `drill`, `set-exit` |
| **Operate** | credentials, client settings, secrets, blast radius, backups, monitoring | [`safe-operation.md`](skills/claude-egress-guard/references/safe-operation.md) |
| **Respond** | exit changed, verification request, leaked credential, suspected bypass | [`safe-operation.md`](skills/claude-egress-guard/references/safe-operation.md) §6 |

The enforcement core is still the binary gate: `claude` itself verifies the
proxy's real exit address, injects the proxy environment, and optionally jails the
whole process tree with a kernel IP allow list. Anything unexpected refuses to
start; there is no fallback. The other three parts exist so that the gate is
installed in the right order and stays meaningful after the first week.

---

## For agents — start here

This repository is written to be consumed by an agent (Hermes, Codex, Claude
Code, or any skill-capable runner), not only by a human reading a README.

```bash
# give the agent the skill (no root, no changes to the host)
curl -fsSL https://raw.githubusercontent.com/yinyues2/claude-egress-guard/main/install.sh \
  | bash -s -- --skill-only --dest ~/.hermes/skills
```

Then say:

> Use the `claude-egress-guard` skill. Interview me for the proxy endpoint, the
> expected exit address, the country and any extra CIDRs; then install, run
> `verify --deep`, drill the failure path and report the PASS/FAIL lines.

What the agent is told, in [`skills/claude-egress-guard/SKILL.md`](skills/claude-egress-guard/SKILL.md):

- **Four facts only** — proxy endpoint, expected exit address, country, allow
  list. Everything else is read from the host instead of asked again.
- **Three authorization tiers** — read-only diagnosis is free; one approval
  covers the plan (install/verify/drill/uninstall); anything that can cut the
  operator's own access is confirmed on the spot.
- **Evidence, not adjectives** — quote the PASS line for every claim, record the
  drill result, never report a layer as working without its output.
- **Hard stops** — never stop ssh/tailscale/docker units, never widen
  `ALLOW_IPS` to `0.0.0.0/0`, never disable a layer to make a check pass, never
  touch account, payment or identity work.

Supporting files: [`AGENTS.md`](AGENTS.md) (machine entry point),
[`references/agent-playbook.md`](skills/claude-egress-guard/references/agent-playbook.md)
(step-by-step with decision points), [`llms.txt`](llms.txt) (link index for
LLM tooling), [`references/troubleshooting.md`](skills/claude-egress-guard/references/troubleshooting.md).

---

## From zero — fresh host, no account yet

Everything below assumes Claude Code is already installed and logged in. If it is
not, the order of operations decides whether the first deployment is safe:
[`references/zero-to-deployed.md`](skills/claude-egress-guard/references/zero-to-deployed.md)
walks nine phases and names who does each one.

```
0  eligibility, one person / one account / one egress     operator
1  host baseline: clock, timezone, disk, IPv6 decision    agent
2  proxy up and proven stable before any signup           agent
3  install Claude Code, then do not launch it             agent
4  install the gate, verify --deep, drill                 agent
5  first login, through the gate, in your own browser     operator
6  first-run settings: no proxy inside the client         operator + agent
7  evidence record, refusal logging on                    agent
8  maintenance: verify after updates, set-exit on drift   agent
```

```bash
claude-egress-guard preflight --proxy http://127.0.0.1:1080 --exit-ip 203.0.113.10 --country JP
```

`preflight` is read-only: it checks platform, systemd, bash, clock, timezone,
IPv6, disk, Node, Claude Code and (when given a proxy) the live exit, then prints
`PASS`/`WARN`/`FAIL` with a blocker count. `FAIL` stops the deployment.

Account creation, payment and identity verification are deliberately **not**
automatable here. The skill forbids an agent from doing them, and the runbook
tells the operator when to stop rather than improvise.

---

## One-command install

```bash
curl -fsSL https://raw.githubusercontent.com/yinyues2/claude-egress-guard/main/install.sh \
  | sudo bash -s -- --proxy http://127.0.0.1:1080 --exit-ip 203.0.113.10 --country JP
```

That command downloads the pinned release, prints the plan, installs the gate,
backs up whatever it replaces, and finishes with `verify --deep`. If any layer
fails it stops and names the layer; it never reports success for a gate that is
not working.

| Flag | Meaning |
| --- | --- |
| `--proxy URL` | local HTTP/mixed proxy the client must use (required) |
| `--exit-ip ADDR` | public IPv4 the proxy must exit from (required) |
| `--country CC` | two-letter country to enforce (optional) |
| `--allow LIST` | extra CIDRs reachable inside the jail, comma separated |
| `--strict-net on\|off` | kernel jail for the process tree (default `on`) |
| `--dry-run` | print the plan, write nothing |
| `--yes` | skip the confirmation prompt (for automation) |
| `--ref REF` | release tag or branch to download (default: pinned tag) |
| `--uninstall` | remove the gate and restore the previous binaries |
| `--skill-only` | copy just the skill into a skills directory |

`203.0.113.10` is documentation address space (RFC 5737); replace it with the
address your proxy actually reports. Loopback and the host's IPv4 DNS resolvers
are allow-listed automatically; add `--allow` for a remote proxy upstream, a
tailnet range, or an internal API.

**Read before you pipe to root.** `install.sh` is a plain shell script with no
obfuscation, and it downloads a tag-pinned tarball rather than a moving branch.
Read it, or clone the repository and run `sudo ./install.sh ...`.

Uninstall, same channel:

```bash
curl -fsSL https://raw.githubusercontent.com/yinyues2/claude-egress-guard/main/install.sh \
  | sudo bash -s -- --uninstall
```

---

## What you get

```
$ sudo claude-egress-guard verify --deep
PASS   config present: /etc/claude-egress-guard.conf
PASS   real binary executable
PASS   gate installed: /usr/local/bin/claude
PASS   gate mirrored: /usr/bin/claude
PASS   egress check: ok exit=203.0.113.10 country=JP
PASS   kernel jail enabled, allow list: 127.0.0.0/8 ::1/128 192.0.2.53/32
PASS   systemd-run available
PASS   IPv6 disabled system-wide
PASS   jail blocks direct egress
PASS   jail still allows the proxy path
---- 0 check(s) failed
```

Every line is an observation rather than a configuration claim: the last two
issue real requests from inside the jail.

```
claude  (any entry point: shell, Python, cron, systemd, absolute path)
  └─ /usr/local/bin/claude           gate: exit check -> proxy env -> jail
       ├─ /usr/bin/claude            same gate (npm updates rewrite this; it self-heals)
       └─ /opt/claude-real/claude    real binary (symlink, follows package updates)
            └─ your proxy            127.0.0.1:1080 -> expected exit address
```

Order of operations on every start:

1. Load `/etc/claude-egress-guard.conf`; missing or unreadable = refuse (77).
2. Restore `/usr/bin/claude` if a package update replaced it with a symlink.
3. Ask the proxy for its exit address and country; mismatch, timeout or HTTP
   error = refuse (77), with no retry and no direct fallback.
4. Export `ALL_PROXY`/`http_proxy`/`https_proxy` (and the lowercase forms) to the
   client and every child, with `NO_PROXY` limited to loopback.
5. If `STRICT_NET=1`, exec inside a transient systemd scope with
   `IPAddressDeny=any` and `IPAddressAllow=<allow list>`, so children inherit a
   kernel-level allow list instead of a promise.

Diagnostics never touch the network: `--version`, `--help` and `--ceg-check`
short-circuit before the probe.

---

## What it guarantees

| Layer | Behaviour |
| --- | --- |
| Exit check | Address and country verified before every start; any mismatch, timeout or error refuses with exit 77 |
| Proxy environment | All six proxy variables exported to the client and every descendant |
| Kernel jail | `IPAddressDeny=any` for the whole process tree; only loopback, the allow list and explicitly allowed CIDRs stay reachable |
| Entry-point coverage | `/usr/local/bin/claude` and `/usr/bin/claude` are both the gate; the real binary lives under `/opt/claude-real` |
| Self-heal | Package self-updates that rewrite `/usr/bin/claude` are repaired on the next invocation |
| Fail-closed | Missing config, missing checker, proxy down, wrong exit, wrong country, no `systemd-run`, not root with `STRICT_NET=1`: all refuse |
| Audit trail | With `LOG_REFUSALS=1`, every refusal goes to journald under the `claude-egress-guard` tag |
| Reversibility | Every replaced file is backed up under `/var/lib/claude-egress-guard/backup/<timestamp>/`; `uninstall` restores it |

---

## Requirements and compatibility

| Item | Requirement |
| --- | --- |
| OS | Linux with systemd 235+ (needed for `IPAddressDeny=`) |
| Shell | bash 4.3+ |
| Tools | `curl`, `install`, `readlink`, `mktemp`, `awk`, `sed` |
| Privileges | root for a real install; `--prefix` for an unprivileged sandbox |
| Claude Code | already installed, npm-global or native installer |
| Proxy | local HTTP or mixed endpoint (SOCKS-only is not usable through the client's proxy variables) |

Verified against: Debian 13 / systemd 257 / Claude Code 2.1.296 (npm-global),
with a residential HTTP proxy on loopback. CI runs the suite on Ubuntu 24.04.

Not verified, not supported: macOS and BSD, WSL, systemd older than 235, rootless
user scopes with `STRICT_NET=1`, Claude running inside containers.

**Cost per start:** one HTTPS round trip through the proxy (roughly 100-400 ms
depending on distance). `--version` and `--help` skip it.

---

## Commands

| Command | Purpose |
| --- | --- |
| `claude-egress-guard preflight [--proxy URL --exit-ip ADDR --country CC]` | read-only readiness check for a fresh host, incl. live exit probe; `--json` for tooling |
| `claude-egress-guard install ...` | plan, back up, install, print the next step (`--dry-run` supported) |
| `claude-egress-guard verify` | static checks + live exit check |
| `claude-egress-guard verify --deep` | adds proof that the jail blocks direct egress and still allows the proxy |
| `claude-egress-guard status` | current policy with proxy credentials masked |
| `claude-egress-guard set-exit --ip ADDR [--country CC]` | follow a rotating exit: probe first, rewrite policy only if the proxy serves that address, then re-verify |
| `claude-egress-guard drill --service UNIT` | stop the proxy unit, prove the gate refuses, restart, wait for recovery |
| `claude-egress-guard show <guard\|check\|config>` | print the installed gate, checker or policy for audit |
| `claude-egress-guard uninstall` | restore the newest backup and remove the gate |

Exit codes: `0` success, `1` verification failed, `2` usage error, `77` the gate
refused to start.

---

## Rotating or changing the exit

Residential exits move. Do not hand-edit the config; ask the gate to follow:

```bash
sudo claude-egress-guard set-exit --ip 198.51.100.23 --country JP
```

It probes the proxy with the candidate address first, refuses if the proxy does
not serve it, rewrites `EXPECTED_IP`/`EXPECTED_COUNTRY` atomically with mode
0600, then runs `verify`.

If the exit moved and you do not know the new address:

```bash
curl -4 -fsS --max-time 8 -x http://127.0.0.1:1080 https://www.cloudflare.com/cdn-cgi/trace
```

Take `ip=` and `loc=` from that output.

---

## Refusal logging

Refusals are otherwise visible only to whoever is watching the terminal. Turn on
journald logging once:

```bash
sudo sed -i 's/^LOG_REFUSALS=0/LOG_REFUSALS=1/' /etc/claude-egress-guard.conf
```

Then:

```bash
journalctl -t claude-egress-guard --since -24h
```

Each entry is `refused: <reason>`. This is the difference between "I think it
never refused" and "here are the eleven times it did".

---

## Everyday operations

| Event | Action |
| --- | --- |
| `npm i -g` or Claude Code self-update | `sudo claude-egress-guard verify --deep` (the alt path is repaired automatically) |
| Proxy exit changed | `sudo claude-egress-guard set-exit --ip NEW --country CC` |
| Proxy moved to a remote relay | add the relay address with `--allow`, then `verify --deep` |
| Want no kernel jail | set `STRICT_NET=0`, then `verify` (expect a WARN); process-tree egress is no longer enforced |
| Suspect a bypass | `status`, then inspect `/proc/<pid>/cgroup` for a `run-r...scope` |

---

## What it does not do

- **It does not create or manage the proxy.** You supply an endpoint that
  already exits where you want, and you keep it alive.
- **It gates one binary.** `npx @anthropic-ai/claude-code` runs the package
  without touching `/usr/local/bin/claude` and is therefore not gated; remove
  that habit or wrap it yourself. A second Claude installation in another prefix
  is also ungated until you gate or remove it.
- **It is not a VPN.** Host services, package managers and other users are
  unaffected; the jail applies only to the Claude process tree.
- **It cannot stop root.** Anyone with root can set `STRICT_NET=0`, edit the
  config or run `/opt/claude-real/claude` directly. This is a guard rail, not a
  mandatory access control boundary.
- **It does not cover containers.** Docker and Kubernetes traffic does not pass
  through the host's output path.
- **It does not make an account safe.** Registration, payment, identity checks
  and provider decisions stay with the account owner; nothing here is meant to
  evade a provider's terms.

More detail, including the full threat model: [SECURITY.md](SECURITY.md).

---

## Manual install from a checkout

```bash
git clone https://github.com/yinyues2/claude-egress-guard.git
cd claude-egress-guard

# one command, same flags as the curl form
sudo ./install.sh --proxy http://127.0.0.1:1080 --exit-ip 203.0.113.10 --country JP

# or drive the CLI directly
sudo skills/claude-egress-guard/scripts/claude-egress-guard install \
  --proxy http://127.0.0.1:1080 --exit-ip 203.0.113.10 --country JP --dry-run
```

---

## Development

```bash
make check        # shellcheck + 44 self-tests + leak scan
make test         # sandboxed suite only (no root, no network)
make lint
make scan
```

The suite installs into a throwaway prefix with fake `curl`, `id`, `logger` and
`systemd-run`, so it neither needs root nor touches the host.

---

## Repository layout

```
install.sh                  one-command installer (tag-pinned download)
AGENTS.md                   machine entry point for agent runners
llms.txt                    link index for LLM tooling
skills/claude-egress-guard/
  SKILL.md                  the deployment skill
  references/               playbook and troubleshooting
  scripts/claude-egress-guard   installer/verifier/drill/uninstall CLI
  scripts/guard-claude.sh   the gate (installed as `claude`)
  scripts/egress-check.sh   exit checker (standalone runnable)
  scripts/selftest.sh       44 sandboxed assertions
  templates/                example policy file
tools/leak-scan.py          blocks credentials, PII and non-documentation IPs
```

---

## License, security, privacy

Apache-2.0 — see [LICENSE](LICENSE). Security model and reporting:
[SECURITY.md](SECURITY.md). Data collection: [PRIVACY.md](PRIVACY.md) — short
version: none, no telemetry, no network calls other than your own proxy probe.
