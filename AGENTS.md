# AGENTS.md

Machine entry point for agent runners. If you are an agent asked to "lock down",
"pin", "verify" or "audit" the egress of Claude Code on a Linux host, read this
file, then load [`skills/claude-egress-guard/SKILL.md`](skills/claude-egress-guard/SKILL.md).

## What this repository is

A deployment skill plus an installer for a fail-closed egress gate in front of
Claude Code. It is not a proxy and not a VPN: it makes the `claude` binary refuse
to start unless traffic leaves through one verified exit.

## Read order

1. `skills/claude-egress-guard/SKILL.md` — the contract (facts, tiers, guardrails).
2. `skills/claude-egress-guard/references/agent-playbook.md` — commands and decision points.
3. `skills/claude-egress-guard/references/troubleshooting.md` — when a check fails.
4. `SECURITY.md` — threat model, known limitations, what is out of scope.

## Operating contract

- Ask the operator for exactly four things: proxy endpoint, expected exit address,
  country to enforce, extra CIDRs. Everything else is read from the host.
- Read-only diagnosis (`--help`, `--dry-run`, `status`, `verify`) needs no extra
  approval once the scope is agreed. One approval covers install, `verify --deep`,
  policy edits and uninstall. Confirm on the spot before anything that can cut the
  operator's own access (ssh, tailscale, the session's network path, reboots).
- Quote the PASS/FAIL line for every claim. A layer without output is not verified.
- Never stop a unit whose name contains ssh, tailscale or docker.
- Never widen `ALLOW_IPS` to `0.0.0.0/0` or a whole private range.
- Never set `STRICT_NET=0` to make a check pass; that is an operator decision with
  a stated trade-off.
- Never touch account registration, payment, identity verification or provider
  decisions.

## Fresh host

If Claude Code is not installed, or the operator has no account yet, read
`skills/claude-egress-guard/references/zero-to-deployed.md` first. The order is:
host baseline → proxy proven stable → install the client **without launching it**
→ install the gate and prove it → first login through the gate → settings →
evidence. Account creation, payment, terms acceptance and identity verification
are operator-only; never do them for someone.

```bash
claude-egress-guard preflight --proxy "$PROXY" --exit-ip "$EXIT_IP" --country "$CC"
```

Read-only. `FAIL` blocks the deployment; `WARN` is a decision the operator must
accept out loud.

## Entry points

```bash
# install the skill only
./install.sh --skill-only --dest ~/.hermes/skills

# full install, unattended
sudo ./install.sh --proxy "$PROXY" --exit-ip "$EXIT_IP" --country "$CC" --yes

# readiness check before anything else
claude-egress-guard preflight --proxy "$PROXY" --exit-ip "$EXIT_IP" --json

# proof
sudo claude-egress-guard verify --deep
sudo claude-egress-guard drill --service "$PROXY_UNIT"
```

Exit codes: `0` ok, `1` verification failed, `2` usage, `77` gate refused.

## What "done" means

`verify --deep` reports `0 check(s) failed`, the drill reports refusal and
recovery, the operator's Claude invocation still works, and you have written down
the version, the exit address, the allow list and the drill result.
