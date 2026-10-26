# Security policy

## Reporting

Use GitHub's private vulnerability reporting on this repository
("Security" → "Report a vulnerability"). Do not open a public issue for anything
that could weaken the gate for deployed users.

Please include: affected version, host distribution and systemd version, the
`verify` output (redact addresses), and the steps to reproduce. Expect an
acknowledgement within 7 days and a decision within 30.

## What this project protects against

1. **Accidental direct egress.** Claude Code or a child process reaching the
   internet from the host's own address because a proxy died, a variable was not
   exported, or the caller was not an interactive shell.
2. **Entry-point bypass.** Invocations from Python, cron, systemd, `sh -c`, or an
   absolute `/usr/bin/claude` path, which a shell function never sees.
3. **Silent regression after package updates.** Claude Code's self-update
   re-creates `/usr/bin/claude` as a symlink; the gate re-installs itself.
4. **Wide-open jail configuration.** The installer refuses empty allow lists and
   the verifier proves direct egress is blocked before reporting success.

## What it does not protect against

- **Root on the host.** Anyone with root can set `STRICT_NET=0`, edit
  `/etc/claude-egress-guard.conf`, run the real binary directly from
  `/opt/claude-real/claude`, or stop the proxy. This is a guard rail, not a
  mandatory access control boundary.
- **A second Claude installation.** Only the pinned binary is gated. If another
  copy exists in a different prefix, it must be removed or gated separately.
- **Container workloads.** Docker/Kubernetes traffic does not pass through the
  host's output path; the jail applies to the transient scope Claude runs in.
- **DNS content.** Name resolution uses the host resolver; the jail only limits
  which resolver addresses are reachable. Use a resolver you trust (and consider
  DNS-over-TLS) if that matters.
- **Proxy compromise or misconfiguration.** If the proxy exits somewhere else,
  the gate refuses to start only when the address differs from `EXPECTED_IP`; it
  cannot tell whether the exit is trustworthy.
- **Provider-side account decisions.** Nothing here affects, prevents, or
  reverses account reviews, verification requests, or suspensions, and it must
  not be used to evade a provider's terms.

## Hardening checklist

- Keep `/etc/claude-egress-guard.conf` at mode `0600` owned by root.
- Never allow `0.0.0.0/0`, `::/0`, or whole private ranges in `ALLOW_IPS`.
- Keep `STRICT_NET=1` unless the host genuinely needs process-tree egress.
- Run `verify --deep` after every package upgrade and after any proxy change.
- Prefer a proxy endpoint that is loopback-only, so the jail does not need a
  remote relay address.
- Audit the gate before trusting it: `claude-egress-guard show guard`.

## Supported versions

The latest `1.x` release receives fixes. Older tags are not patched.

## Disclosure

We credit reporters by name or handle if they want, and we publish an advisory
after a fix is available. Reports that only show "root can disable it" are out of
scope; reports that show an unprivileged bypass, a jail escape, or a
check-that-always-passes are in scope.
