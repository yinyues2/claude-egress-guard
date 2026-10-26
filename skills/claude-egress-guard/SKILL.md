---
name: claude-egress-guard
description: "Use when pinning Claude Code to one egress on Linux — installs a fail-closed gate, kernel net jail, and drills it."
version: 1.0.0
author: claude-egress-guard contributors
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [claude, egress, network, systemd, fail-closed, security]
    category: devops
---

# Claude Egress Guard

Install a fail-closed egress gate in front of Claude Code on a Linux host: every
invocation must pass an exit-address check, the client and its children get proxy
variables, and (by default) the whole process tree is jailed with a kernel-level
IP allow list. Anything unexpected refuses to start instead of falling back.

## When to use

- The operator runs Claude Code on a VPS or remote Linux box and wants its traffic
  to leave through one known residential/proxy exit, not the datacenter IP.
- An existing guard is only a shell function or a `claude()` alias, so cron,
  Python, systemd or absolute paths can bypass it.
- The proxy can die or change address and nobody notices until the IP history is
  already polluted.
- The operator asks to "lock down", "pin", or "verify" the Claude egress, or to
  prove it still works after a package update.

Do not use it to hide from a provider, to run multiple accounts, to rotate
identities, or as a substitute for the proxy itself. It gates one binary; it does
not configure networking.

## Facts to collect once

Ask only what cannot be read from the host. Do not ask again later.

1. **Proxy endpoint** — a local HTTP/mixed URL, e.g. `http://127.0.0.1:1080`.
2. **Expected exit address** — the address the proxy reports, ideally obtained by
   running the probe once through it (`curl -x <proxy> https://www.cloudflare.com/cdn-cgi/trace`).
3. **Country code** — the ISO code that exit reports, if the operator wants it enforced.
4. **Kernel jail** — on (default) unless the host's Claude work needs unrestricted
   egress, and which extra CIDRs must stay reachable (tailnet, internal APIs).
5. **Proxy unit name** — only needed for `drill`.

Never ask for credentials, subscription links, or the contents of the proxy config.

## Authorization tiers

| Tier | What it covers | How to proceed |
| --- | --- | --- |
| A — read-only | `--help`, `--dry-run`, `status`, `verify` without `--deep`, reading config | Do it without asking again once the scope is agreed |
| B — one approval for the plan | `install`, `verify --deep`, editing the allow list, `uninstall` | Present the plan (paths, backup, allow list, what it replaces), then execute |
| C — confirm on the spot | Stopping a service that carries the session, changing SSH, rebooting, anything that could lock the operator out | Write the exact command, wait for an explicit yes |

`drill` stops and starts the proxy unit. Treat it as B when the unit is unrelated
to the session, C when it is the only path to the host.

## Procedure

```bash
S=./skills/claude-egress-guard/scripts

# A: plan
sudo "$S/claude-egress-guard" install \
  --proxy "$PROXY" --exit-ip "$EXIT_IP" [--country "$CC"] [--allow "$CIDRS"] --dry-run

# B: install (backs up anything it replaces)
sudo "$S/claude-egress-guard" install \
  --proxy "$PROXY" --exit-ip "$EXIT_IP" [--country "$CC"] [--allow "$CIDRS"]

# B: prove it
sudo "$S/claude-egress-guard" verify --deep

# B/C: prove it under failure
sudo "$S/claude-egress-guard" drill --service "$PROXY_UNIT"
```

What the operator should see when it is working:

- `verify` prints one PASS line per layer and ends with `0 check(s) failed`.
- `verify --deep` additionally proves direct egress is blocked inside the jail and
  the proxy path still works.
- `drill` prints `PASS gate refused to start with the proxy down` and
  `PASS gate recovered after Ns`.
- A real Claude invocation still works afterwards (ask before spending quota).

## Reading failures

| Exit | Meaning | Next step |
| --- | --- | --- |
| 77 | Gate refused: config missing, proxy unreachable, exit/country mismatch, jail unavailable or not root | Run the checker directly to see the reason: `/usr/local/lib/claude-egress-guard/egress-check.sh` |
| 1 | `verify` found a failed layer | Fix the named layer; never silence it |
| 2 | Usage error | Re-read `--help` |

Do not "fix" a refusal by setting `STRICT_NET=0` unless the operator explicitly
asks for that trade-off. Do not widen `ALLOW_IPS` to `0.0.0.0/0`.

## Guardrails

- Never stop a unit whose name matches ssh, tailscale or docker; `drill` refuses
  this itself, and so should you.
- Never edit `/etc/claude-egress-guard.conf` to make a test pass. Changing policy
  is a B-tier decision with the operator.
- Do not claim a layer passed without its output. Quote the PASS/FAIL line.
- If the host has no systemd or is not root, install with `--strict-net off` only
  after saying what protection is lost.
- Package self-updates re-create `/usr/bin/claude` as a symlink; the gate repairs
  itself on the next invocation. After a manual upgrade, run `verify` instead of
  assuming.
- Leave account work (registration, payment, identity checks) to the operator.

## Reporting template

```
Done:      gate installed at <paths>, real binary pinned to <path>, jail <on/off>
Evidence:  verify -> <n> layers PASS; exit check -> <ok/fail>; drill -> <pass/fail>
Left:      <what the operator still has to do, if anything>
```

## References

- `references/agent-playbook.md` — full command sequence, allow-list rules, evidence record
- `references/troubleshooting.md` — symptom → cause → fix table
