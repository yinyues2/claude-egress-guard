# Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Claude exits with `77` right after install | Exit check failed (proxy down, wrong address, wrong country) or config missing | Run `/usr/local/lib/claude-egress-guard/egress-check.sh` for the reason; fix the proxy or the policy |
| `claude-egress-guard: STRICT_NET is on but this process is not root` | The jail needs root to create a system scope | Run as root, or set `STRICT_NET=0` and accept that process-tree egress is unenforced |
| `Failed to parse IP address prefix: localhost` | `IPAddressAllow=` accepts CIDR only, not names | Use `127.0.0.0/8 ::1/128 ...` |
| Everything fails with `could not resolve host` inside a Claude session | The jail blocks the DNS resolvers in `/etc/resolv.conf` | Add them: `--allow 192.0.2.53/32` (or fix resolvers and re-run `install`) |
| `verify --deep` says `jail blocks the proxy path` | The proxy upstream is not loopback and is not allow-listed | Add the exact upstream address to `ALLOW_IPS` |
| `verify --deep` says `jail did NOT block direct egress` | `ALLOW_IPS` is too wide (`0.0.0.0/0`, whole private ranges), or the host has no cgroup BPF support | Narrow the allow list; check `systemd --version` and kernel BPF support |
| `verify` says `alternative path is still a symlink` | A package update re-created `/usr/bin/claude` and nothing invoked the gate since | Invoke `claude --version` once (self-heal) or run `install` again |
| `curl` works but Claude reports network errors | Not every client honours proxy variables; some tools open raw sockets | That is exactly what the jail is for — check `ALLOW_IPS`, or route the tool through the proxy explicitly |
| Exit check passes but a second egress exists | Multiple proxies or a second route on the host | `claude-egress-guard status`, then confirm the process tree is inside a `run-r...scope` |
| `drill` refuses to stop a unit | Unit name matches ssh/tailscale/docker | Use a proxy unit name that does not collide, and confirm stopping it is safe |
| `drill` says the gate recovered but Claude still fails | The client, not the gate, is broken (auth, quota, version) | Run `claude --version` and `claude auth status` outside the gate scope to compare |
| `npm i -g` re-created the symlink and you want certainty | Self-heal is best-effort on the next invocation | `sudo claude-egress-guard verify --deep` after every manual upgrade |
| Two Claude installations (`npm-global` and native) | The gate pins one real binary; the other stays callable by absolute path | Remove the unused install, or add a second gate for it and verify both |
| `npx @anthropic-ai/claude-code` works and still leaves from the host address | `npx` runs the package directly, never `/usr/local/bin/claude` | Stop using `npx` on that host, or wrap it with its own egress check |
| A proxy in `~/.claude/settings.json` seems to win | Client settings are applied after the gate exports its variables | Remove the proxy from the client settings; the gate owns egress |
| Claude in Docker/Kubernetes is not gated | Container traffic does not use the host's output path | Run Claude on the host, or gate inside the container |
| `set-exit` refuses with `proxy does not serve ...` | The proxy is not exiting from that address right now | Check the proxy; never force the value into the config by hand |
| `journalctl -t claude-egress-guard` is empty | `LOG_REFUSALS=0`, or nothing has been refused | Set it to 1; entries only appear when a refusal happens |
| `install.sh` says `no terminal for confirmation` | Piped stdin cannot answer the prompt | Re-run with `--yes` |

## Reading `verify` output

- `PASS` — layer observed working.
- `WARN` — layer not applicable or intentionally relaxed (jail off, IPv6 enabled). Not a failure, but say so in the report.
- `FAIL` — the deployment is not doing what it claims; do not report success.

## Recovering from a broken install

```bash
sudo claude-egress-guard uninstall     # restores the newest backup
# or, if the CLI itself is gone:
ls /var/lib/claude-egress-guard/backup/
# /usr/bin/claude is usually a symlink to the package binary:
ln -sfn /path/to/package/bin/claude /usr/bin/claude
```

Backups are never deleted automatically.
