# Contributing

Thanks for taking a look. This is a security-adjacent tool, so the bar for
changes is "does not weaken the default behaviour".

## Ground rules

1. **No real infrastructure in the repository.** Use documentation address space
   (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`), `example.com`, and
   `127.0.0.1` for local endpoints. Never commit production IPs, hostnames,
   proxy credentials, subscription links, or account identifiers.
2. **Fail closed.** A new code path that can start Claude without a passing exit
   check will not be merged. If a check cannot run, refuse.
3. **No new network calls.** The checker talks to the endpoints in the config and
   nothing else.
4. **No policy shortcuts.** Do not add flags that silently disable a layer; make
   the trade-off explicit and documented, as `--strict-net off` does.

## Style

- Bash, 4-space-tab indentation, `set -u`, no `eval`, no unquoted expansions of
  paths.
- Every script must pass `shellcheck -x -S warning`.
- Prefer small functions with a single exit path; keep the gate readable, since
  operators are expected to audit it.
- Comments explain *why*, not *what*.

## Testing

```bash
bash skills/claude-egress-guard/scripts/selftest.sh
shellcheck -x -S warning skills/claude-egress-guard/scripts/*
python3 tools/leak-scan.py
```

Add a case to `selftest.sh` for every behaviour change. The suite runs in a
temporary prefix with fake `curl`, `id` and `systemd-run`; it must stay
root-free and network-free.

## Pull requests

- One concern per PR.
- Describe the failure mode being fixed and the evidence that it is fixed.
- If you change the config schema, update the template, the example in the
  README and the troubleshooting table in the same PR.

## Commit messages

Short imperative subject, wrapped body explaining the failure and the fix.

## Security issues

Do not open a public PR or issue for a bypass. Use the private reporting channel
described in [SECURITY.md](SECURITY.md).
