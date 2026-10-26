---
name: claude-egress-guard
description: "Use when deploying or auditing Claude Code on Linux — one-stop safe setup: preflight, egress gate, operation baseline, incident drills."
version: 1.3.0
author: claude-egress-guard contributors
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [claude, egress, network, systemd, fail-closed, security]
    category: devops
---

# Claude Code: safe deployment and operation

A one-stop skill for running Claude Code on a Linux host you control: bring a bare
machine to a working, gated client, keep it inside one verified egress, and know
what to do when something goes wrong.

Four parts, in the order they matter:

| Part | What it covers | Where |
| --- | --- | --- |
| **Deploy** | eligibility, host baseline, proxy proven stable, client installed but not launched, first login through the gate | `references/zero-to-deployed.md`, `preflight` |
| **Egress** | one verified exit, proxy injection, kernel jail for the whole process tree, self-heal after updates, no fallback | `install` / `verify --deep` / `drill` / `set-exit` |
| **Operate** | credentials, client settings, secrets, working-directory blast radius, backups, monitoring | `references/safe-operation.md` §1-5 |
| **Respond** | exit change, verification request, leaked credential, suspected bypass | `references/safe-operation.md` §6 |

The enforcement core is still one binary: `claude` becomes a gate that refuses to
start when the exit is not the one you configured. The rest of the skill exists so
that the gate is installed in the right order, and stays meaningful afterwards.

## When to use

- The operator runs Claude Code on a VPS or remote Linux box and wants its traffic
  to leave through one known residential/proxy exit, not the datacenter IP.
- An existing guard is only a shell function or a `claude()` alias, so cron,
  Python, systemd or absolute paths can bypass it.
- The proxy can die or change address and nobody notices until the IP history is
  already polluted.
- The operator asks to "lock down", "pin", or "verify" the Claude egress, or to
  prove it still works after a package update.
- The operator asks whether an existing Claude deployment is *safe* in general:
  credentials, client settings, secrets, backups, monitoring, and what to do in
  an incident. Audit against `references/safe-operation.md`.
- The host is fresh and the operator has never had an account: start with
  `references/zero-to-deployed.md` instead of improvising an order of operations.

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

If you have the full repository, `install.sh` wraps the same sequence and is the
preferred entry point. It prints the plan, installs, backs up, then runs
`verify --deep` and stops on the first failed layer:

```bash
sudo ./install.sh --proxy "$PROXY" --exit-ip "$EXIT_IP" [--country "$CC"] [--allow "$CIDRS"]
```

With only the skill directory installed, drive the CLI directly:

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

## Fresh host, no account yet

Do not start with the installer. The order is what makes a first deployment safe,
and two of the phases are not yours to run. Follow
`references/zero-to-deployed.md`; the short form:

| Phase | Goal | Who |
| --- | --- | --- |
| 0 | Eligibility, one person/one account/one egress, payment in your own name | operator decides; you state the stop conditions |
| 1 | Host baseline: updates, clock, timezone, disk, IPv6 decision | you |
| 2 | Proxy up and proven stable before any account action | you |
| 3 | Install Claude Code, then **do not launch it** | you |
| 4 | Install the gate and prove it: `verify --deep` + `drill` | you |
| 5 | First login through the gate, in the operator's own browser | operator |
| 6 | First-run settings: no proxy inside the client, updates on | operator decides, you apply |
| 7 | Evidence record + `LOG_REFUSALS=1` | you |
| 8 | Maintenance: `verify --deep` after updates, `set-exit` on rotation | you |

Run the read-only readiness check before phase 2 and again before phase 4:

```bash
claude-egress-guard preflight --proxy "$PROXY" --exit-ip "$EXIT_IP" --country "$CC"
```

`FAIL` items block. `WARN` items are decisions the operator must accept in
writing, not things to paper over.

**Hard stop:** never create an account, enter payment details, accept terms, or
handle identity documents. If eligibility is unclear, stop and say so.

## Changing policy

- **Rotating exit.** `sudo claude-egress-guard set-exit --ip NEW [--country CC]`
  probes the proxy with the candidate address first, refuses if the proxy does
  not serve it, rewrites the policy atomically (mode 0600) and re-runs `verify`.
  Never hand-edit `EXPECTED_IP` from a number the operator guessed.
- **Audit trail.** Set `LOG_REFUSALS=1` in `/etc/claude-egress-guard.conf`, then
  read `journalctl -t claude-egress-guard`. Prefer this over asking the operator
  "did it ever refuse?".
- **Anything else** (allow list, jail on/off) is a B-tier edit followed by
  `verify --deep`.

## Out of scope

State these plainly instead of implying coverage:

- `npx @anthropic-ai/claude-code`, and any second Claude installation outside the
  gated paths.
- Containers whose traffic does not use the host's output path.
- Root on the host: root can disable the gate, edit the policy or run the real
  binary directly.
- macOS, BSD, WSL, systemd older than 235.
- SOCKS-only proxies: the client's proxy variables need an HTTP/mixed endpoint.

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
- `references/zero-to-deployed.md` — phase-by-phase runbook for a fresh host with no account
- `references/safe-operation.md` — credentials, client settings, secrets, blast radius, monitoring, incident response
- `references/troubleshooting.md` — symptom → cause → fix table
