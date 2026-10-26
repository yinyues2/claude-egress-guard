# Agent playbook

Concrete sequence for deploying `claude-egress-guard` on a Linux host. Follow it
in order; each step names what to check before moving on.

## 0. Read the host, do not assume it

```bash
uname -srm                      # Linux, kernel
id -u                           # 0 for a real install
command -v systemd-run systemctl curl install
systemctl --version | head -1   # 235+ for IPAddressDeny
readlink -f "$(command -v claude)"   # real binary; empty = not installed
```

Record the current state before changing anything:

```bash
ls -l /usr/bin/claude /usr/local/bin/claude 2>/dev/null
systemctl list-units --type=service | grep -iE 'proxy|xray|sing-box|clash' | head
```

## 1. Learn the exit the proxy really gives

```bash
curl -4 -fsS --max-time 8 -x "$PROXY" https://www.cloudflare.com/cdn-cgi/trace
```

Take `ip=` as `--exit-ip` and `loc=` as `--country`. If the proxy needs a
hostname that only resolves on the host, run it on the host, not from your own
machine.

Two independent sources are better than one. Cross-check with a second endpoint
(e.g. `https://ipinfo.io/json` through the same proxy). Geo databases disagree
often enough that a single outlier should not be treated as the truth.

## 2. Decide the allow list

Inside the jail only these stay reachable:

- `127.0.0.0/8` and `::1/128` — the local proxy listener, local sockets and
  `systemd-resolved` on `127.0.0.53`. A `/32` would break DNS on resolved hosts.
- the host's IPv4 DNS resolvers (the installer adds them automatically).
- anything passed with `--allow`:
  - the **proxy upstream** when it is not loopback (a remote relay address);
  - a **tailnet** range when other agents reach the host that way;
  - internal API endpoints the operator's work depends on.

Rules of thumb:

- Never use `0.0.0.0/0` or a whole `10.0.0.0/8` "to be safe".
- If `verify --deep` reports `jail blocks the proxy path`, the proxy upstream is
  missing from the list — add the exact address, not a wide range.
- If DNS breaks inside the jail (`could not resolve host`), `/etc/resolv.conf`
  points at resolvers that are not allow-listed. Re-run `install` after fixing
  resolvers, or add them with `--allow`.

## 3. Install

```bash
sudo claude-egress-guard install \
  --proxy "$PROXY" \
  --exit-ip "$EXIT_IP" \
  --country "$CC" \
  --allow "$EXTRA_CIDRS"
```

What it writes (all under `--prefix`, default `/`):

```
/etc/claude-egress-guard.conf                       mode 0600, the only policy file
/usr/local/lib/claude-egress-guard/guard-claude.sh  the gate source
/usr/local/lib/claude-egress-guard/egress-check.sh  the exit checker
/usr/local/bin/claude                               gate
/usr/bin/claude                                     gate (disable with --no-alt)
/usr/local/sbin/claude-egress-guard                 this CLI
/opt/claude-real/claude                             symlink -> real package binary
/var/lib/claude-egress-guard/backup/<timestamp>/    whatever was replaced
```

If `/usr/bin/claude` was a symlink (npm-global install), it is backed up as a
symlink and restored by `uninstall`.

## 4. Verify

```bash
sudo claude-egress-guard verify --deep
```

Pass criteria, one line each: config present, real binary executable, gate
installed, alternative path is the gate and not a symlink, egress check `ok`,
jail enabled with a non-empty allow list, `systemd-run` present, jail blocks
direct egress, jail allows the proxy path.

Then prove it end to end **without spending quota**:

```bash
sudo -u <operator> claude --version          # passthrough, no network
CEG_CONF=/etc/claude-egress-guard.conf claude --ceg-check   # gate check only
```

Only run a real prompt if the operator approves it.

## 5. Drill

```bash
sudo claude-egress-guard drill --service "$PROXY_UNIT" --wait 30
```

Expected output: `PASS gate refused to start with the proxy down`, then
`PASS gate recovered after Ns`. The trap restarts the unit even on failure.

Do not run the drill when the proxy unit is also the path you are connected
through. `drill` refuses names containing ssh/tailscale/docker, but a custom unit
name can still be load-bearing — ask.

## 6. Record evidence

Write a short record next to the deployment (this is for the operator, not a
public file):

```
host:        <hostname or alias>
date:        <UTC timestamp>
proxy:       <endpoint, credentials stripped>
exit:        <address> / <country>
jail:        on, allow=<cidrs>
verify:      <n> PASS, 0 FAIL (deep: yes/no)
drill:       refused-with-proxy-down=yes, recovered-after=<n>s
package:     <claude --version output>
```

## 7. Maintenance

| Event | Action |
| --- | --- |
| `npm i -g @anthropic-ai/claude-code` or built-in update | `verify --deep`; the gate self-heals `/usr/bin/claude` |
| Proxy exit address changed | update `EXPECTED_IP`, run `verify` |
| Proxy moved to a remote relay | add the relay address to `ALLOW_IPS` |
| Operator wants no kernel jail | `STRICT_NET=0`, then `verify` (expect a WARN) |
| Suspected bypass | `claude-egress-guard status`, then list processes containing `claude` and check their cgroup: `cat /proc/<pid>/cgroup` should show a `run-r...scope` |

## Failure handling

- A failed layer is never resolved by disabling the layer. Fix the layer or
  record why it cannot be met and tell the operator.
- If the host has no systemd, install with `--strict-net off` **and say** that
  process-tree egress is no longer enforced.
- If the real binary cannot be found, stop and ask for its path; do not guess.
