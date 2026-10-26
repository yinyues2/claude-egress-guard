# Changelog

All notable changes to this project are documented here. The format follows
Keep a Changelog; versions use semantic versioning.

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
