# Changelog

All notable changes to this project are documented here. The format follows
Keep a Changelog; versions use semantic versioning.

## [1.3.0] - 2026-10-27

### Changed

- Repositioned from "an egress gate" to a one-stop Claude Code deployment and
  operation skill. The binary gate stays the enforcement core; the skill now names
  four parts explicitly — deploy, egress, operate, respond — in `SKILL.md`, both
  READMEs, `AGENTS.md` and `llms.txt`.

### Added

- `references/safe-operation.md`: credential handling, client settings (no proxy
  in `settings.json`, keep permission prompts, review hooks and MCP servers,
  one installation), secrets in the working tree, working-directory blast radius,
  monitoring, incident response for exit changes / verification requests / leaked
  credentials / suspected bypass, and update discipline.

## [1.2.0] - 2026-10-27

### Added

- `references/zero-to-deployed.md`: a nine-phase runbook for a host with nothing
  installed and an operator with no account — eligibility, host baseline, proxy
  proven stable before signup, client installed but not launched, gate proven,
  first login through the gate, first-run settings, evidence, maintenance. Each
  phase names who runs it and where to stop.
- `claude-egress-guard preflight [--proxy URL] [--exit-ip ADDR] [--country CC] [--json]`:
  read-only readiness check for platform, systemd, bash, clock, timezone, IPv6,
  disk, Node, Claude Code and the live exit, with `PASS`/`WARN`/`FAIL` and a
  blocker count. Nothing is written.
- README (both languages) and `AGENTS.md` gained a "from zero" section that puts
  the runbook ahead of the installer and states plainly that account work is
  operator-only.
- Two self-tests for `preflight`: valid JSON and a bounded exit code.

## [1.1.0] - 2026-10-27

### Added

- `install.sh`: one-command installer, usable from a checkout or piped from
  `raw.githubusercontent.com`. Downloads a tag-pinned release when it is not run
  from a checkout, prints the plan, backs up replaced files, then runs
  `verify --deep`; `--skill-only`, `--uninstall`, `--dry-run`, `--yes`, `--ref`.
- `claude-egress-guard set-exit --ip ADDR [--country CC]`: follows a rotating
  residential exit. Probes the proxy with the candidate address, refuses if the
  proxy does not serve it, rewrites the policy atomically (mode 0600) and
  re-verifies.
- `LOG_REFUSALS=1`: refusals are written to journald under the
  `claude-egress-guard` tag, so "did it ever refuse?" is a query.
- `AGENTS.md`, `llms.txt` and a `Makefile` (`make check`), so agent runners and
  contributors have machine entry points.
- README restructured around two audiences: agents installing the skill, and
  humans running one command. Adds a real `verify --deep` sample, a compatibility
  table, per-start cost, refusal logging, exit rotation and an explicit
  "what it does not do" section (`npx`, second installs, containers, root,
  SOCKS-only proxies).
- Eleven new self-tests (42 total): set-exit accept/refuse/restore, refusal logging,
  and the installer's `--help`, `--skill-only` and missing-argument behaviour.

### Changed

- The default allow list uses `127.0.0.0/8` instead of `127.0.0.1/32`, so
  `systemd-resolved` on `127.0.0.53` keeps working inside the jail.
- `verify --deep` no longer aborts on unset proxy variables when the config is
  missing; it reports the failed layer.
- The real binary is checked before the diagnostic passthrough, so a broken pin
  reports the actual reason instead of a shell `command not found`.

## [1.0.0] - 2026-10-27

### Added

- Fail-closed gate for Claude Code: exit-address and country check before every
  start, proxy environment injection, refusal with exit code 77 when anything is
  missing or mismatched.
- Binary-level coverage: the gate is installed as both
  `/usr/local/bin/claude` and `/usr/bin/claude`, with the real binary pinned at
  `/opt/claude-real/claude`, so Python, cron, systemd and absolute-path callers
  are covered.
- Optional kernel-level jail (`STRICT_NET`, default on): the whole Claude process
  tree runs in a transient systemd scope with `IPAddressDeny=any` and an explicit
  allow list (loopback, proxy upstream, DNS resolvers, operator-supplied CIDRs).
- Self-heal after package updates, which re-create `/usr/bin/claude` as a
  symlink.
- Installer with `--dry-run`, timestamped backups of everything it replaces, and
  an allow list that automatically includes loopback and the host's IPv4 DNS
  resolvers.
- `verify` (static + live checks), `verify --deep` (proves the jail blocks direct
  egress and still allows the proxy), `status` (credentials masked), `drill`
  (stops and restarts the proxy unit, proves refusal and recovery), `uninstall`
  (restores from backup), `show` (prints the gate for audit).
- Agent skill (`skills/claude-egress-guard`) with authorization tiers, an
  operator interview limited to four facts, an evidence record template and a
  troubleshooting table.
- Sandboxed self-test suite (31 assertions) using fake `curl`, `id` and
  `systemd-run`; runs without root or network.
- Repository guard rails: shellcheck in CI, a leak scanner that rejects
  credentials, personal identifiers and non-documentation IP addresses, and an
  editor/git configuration that keeps line endings stable.
