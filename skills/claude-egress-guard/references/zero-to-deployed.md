# Zero to deployed

For a host that has never run Claude Code and an operator who has never had an
account. Every phase states who does it, what to run, the checkpoint that ends
the phase, and the conditions that mean **stop**.

Nothing here creates, purchases or verifies an account. Those steps are the
operator's, by design: an agent must never register an account, enter payment
details, accept terms, or handle identity documents on someone's behalf.

## Who does what

| Work | Operator | Agent |
| --- | --- | --- |
| Eligibility, terms, region | decides | states the rule and stops if unclear |
| Host baseline, proxy, installs | approves | executes and verifies |
| Account creation, payment, verification | only | never |
| Login codes | pastes them, once | may pass a code through, never logs it |
| Gate install, verify, drill, evidence | approves | executes and records |

## Phase 0 — Decide before you build

Decide, in this order, and stop at the first "no":

1. **Eligibility.** Does the provider offer service in your region under its
   current terms? If it does not, stop here. This project must not be used to
   circumvent a regional restriction, an identity check, or an account ban.
2. **One person, one account.** No shared logins, no resale, no "team" of
   strangers on a personal plan.
3. **One egress.** The address you sign up from should be the address you use
   daily. Hopping countries between signup, payment and use creates
   contradictions no tool can fix.
4. **Your own payment method.** Your card or your app-store account, in your
   name, with receipts you can produce later.
5. **On hand:** an email you control with 2FA, a phone number that can receive a
   code if asked, and a recovery-code store.

If a later phase asks for something you do not have (a document, a local number,
a verification you cannot truthfully complete), stop and reassess. Do not
improvise identity material.

## Phase 1 — Host baseline

Target: a fresh Linux VPS you control. The vendor's published requirements are
**4 GB RAM, x86-64 or ARM64, Ubuntu 20.04+ / Debian 10+ / Alpine 3.19+**; this
project has been tested on Debian 12/13 and Ubuntu 22.04/24.04. A 2 GB box works
only with swap and is not a good baseline — Claude Code is a Node/Bun binary and
runs out of memory mid-task.

```bash
# 1. base packages: curl is needed by the installer and by the egress checker,
#    ca-certificates by every TLS probe. Minimal images often lack both.
apt-get update
apt-get -y install curl ca-certificates gnupg git
apt-get -y upgrade

# 2. time: a wrong clock breaks OAuth codes and TLS at the same time
timedatectl set-timezone <Your/Real_Timezone>   # where you actually are
timedatectl set-ntp true
timedatectl status          # expect: System clock synchronized: yes

# 3. swap on a small host (skip if you have 4 GB or more)
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
free -h

# 4. room for the client, downloads and backups
df -h /var /home

# 5. optional on a single-stack host: remove IPv6 ambiguity
printf 'net.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1\n' \
  > /etc/sysctl.d/99-disable-ipv6.conf
sysctl --system
```

Do not change inbound firewall rules until you have confirmed SSH still works;
the gate only needs **outbound**. If you run a default-deny inbound policy, allow
your SSH port before anything else.

Checkpoint: clock synchronised, timezone is where you actually are, at least 10 GB
free where the client and its cache live, swap present on a 2 GB host.

Then run the read-only readiness check:

```bash
claude-egress-guard preflight
```

It reports `PASS`/`WARN`/`FAIL` per item and a blocker count; `FAIL` items must
be fixed before going on, `WARN` items are decisions you accept explicitly.

## Phase 2 — Proxy first, account second

Never create an account from an address you have not tested.

1. Bring up your proxy as a **local HTTP or mixed** listener, e.g.
   `127.0.0.1:1080`. SOCKS-only does not work: the client's proxy variables
   speak HTTP.
2. Make it survive a reboot before you depend on it:

   ```bash
   systemctl list-units --type=service --all | grep -i <your-proxy-name>
   systemctl enable --now <your-proxy-unit>
   systemctl is-enabled <your-proxy-unit>    # expect: enabled
   ```

   If your proxy is a plain script rather than a unit, write the unit first. A
   gate that refuses because the proxy never came back after a reboot is
   fail-closed and correct, but it is also an outage you chose not to prevent.
3. Prove the exit, three times, ten minutes apart:

   ```bash
   for i in 1 2 3; do
     curl -4 -fsS --max-time 8 -x http://127.0.0.1:1080 \
       https://www.cloudflare.com/cdn-cgi/trace | grep -E '^(ip|loc)='
     sleep 600
   done
   ```

4. Decide the allow list now:

   | Entry | When |
   | --- | --- |
   | `127.0.0.0/8`, `::1/128` | always, added automatically |
   | host IPv4 DNS resolvers | automatic; add manually if the jail reports DNS failures |
   | proxy upstream address | when the proxy dials a remote relay rather than a local daemon |
   | tailnet range | when other machines reach this host over Tailscale |

Checkpoint: the same address and country on all three probes. If it moves, fix
the proxy before creating anything — a residential exit that rotates hourly is
the wrong foundation for a first account.

```bash
claude-egress-guard preflight --proxy http://127.0.0.1:1080 \
  --exit-ip <ADDR> --country <CC>
```

**DNS is not tunnelled.** Name resolution still leaves from the host's resolvers;
the jail only decides which resolvers are reachable. If your threat model
includes DNS metadata, set `CLAUDE_CODE_PROXY_RESOLVES_HOSTS=1` so the proxy
resolves names, or accept that DNS is out of scope here.

## Phase 3 — Install Claude Code, do not launch it

Two supported layouts. Pick one; do not install both.

**A. Vendor installer (default, self-updating).** Run it as the account that will
use Claude, not with `sudo`:

```bash
curl -fsSL https://claude.ai/install.sh | bash
# puts ~/.local/bin/claude -> ~/.local/share/claude/versions/<ver>
# and appends ~/.local/bin to PATH in .bashrc
claude --version
command -v claude          # expect ~/.local/bin/claude
```

**B. npm (no vendor auto-updater).** Node 18+ is required:

```bash
node -v || apt-get -y install nodejs npm     # or install a current LTS first
npm i -g @anthropic-ai/claude-code
claude --version
command -v claude          # expect /usr/local/bin/claude or /usr/bin/claude
```

Whichever you choose, **that path is what must be gated**. `~/.local/bin` comes
before `/usr/local/bin` in the PATH the vendor installer writes, so a gated
`/usr/local/bin/claude` does not protect a vendor install — pass
`--native-path ~/.local/bin/claude` in the next phase.

Do **not** run `claude` yet. Starting it now opens the login flow before the gate
exists, which is the exact situation this project exists to prevent. `claude
--version` is safe: it prints and exits without a session.

Checkpoint: `claude --version` prints a version, `command -v claude` prints the
path you are going to gate, and nothing has started a session.

## Phase 4 — Install the gate, prove it

```bash
# vendor installer layout
curl -fsSL https://raw.githubusercontent.com/yinyues2/claude-egress-guard/main/install.sh \
  | sudo bash -s -- --proxy http://127.0.0.1:1080 --exit-ip <ADDR> --country <CC> \
      --native-path ~/.local/bin/claude

# npm layout: drop --native-path
```

The installer ends with `verify --deep`, which must print `0 check(s) failed`.
`verify` also checks PATH precedence: if `command -v claude` resolves to
something that is not the gate, it fails instead of reporting a clean host.

Then drill the failure path:

```bash
sudo claude-egress-guard drill --service <your-proxy-unit>
```

Checkpoint: `verify --deep` clean, drill reports `PASS gate refused to start with
the proxy down` and `PASS gate recovered after Ns`.

Stop if any layer fails. Do not log in through a gate that has not proven itself:
the first login is the most valuable traffic you will ever send.

## Phase 5 — First login, through the gate

```bash
claude auth login
```

- The CLI prints a URL and waits. Open it in the browser that is already signed
  in to your account, approve, and paste the code back into the terminal.
- Run this in a real TTY. With no browser on the host the CLI cannot open one,
  but it still prints the URL; copy it to your own machine.
- Codes are single use and expire in minutes. Never paste one into a chat, a
  ticket, a log or a shell history.
- If an orchestrator passes the code through stdin, it must not echo it.
- Credentials land in `~/.claude/.credentials.json` (mode 600). Do not copy that
  file between machines: it is a session, not a configuration.

Checkpoint:

```bash
claude auth status                   # through the gate
claude doctor                        # read-only settings/install diagnostics
claude -p 'Reply with exactly: OK'   # costs a request; ask before running
```

`claude doctor` is only meaningful after the gate exists: before that it would
start the client ungated.

Stop if the exit changed between phase 2 and now: re-run `verify` and
`set-exit` first.

## Phase 6 — First-run settings

- **Do not put a proxy in `~/.claude/settings.json`, including its `env` block.**
  The gate owns egress; a second value inside the client is the fastest way to
  send traffic around it.
- Keep permission prompts on. Do not use `--dangerously-skip-permissions` on a
  host that holds credentials.
- Review hooks and MCP servers before enabling them; both execute code with your
  privileges.
- Set `permissions` deliberately for the work this host does; the default
  prompt-per-tool behaviour is the safer starting point.
- Do not hand-edit `~/.claude.json`; it holds account and per-project trust state.
- Do not enable a second Claude installation, an `npx` alias, or a wrapper that
  calls the real binary — each one is an ungated path.

## Phase 7 — Record the evidence

Write this down next to the deployment (not in a public file). A template lives
at `templates/evidence.md`:

```
host:        <hostname>            date: <UTC timestamp>
os:          <distro + kernel>     systemd: <version>
claude:      <version + install path>
proxy:       <endpoint, credentials stripped>
exit:        <address> / <country>   allow: <CIDRs>
verify:      <n> PASS, 0 FAIL (deep: yes)
drill:       refused-with-proxy-down=yes, recovered-after=<n>s
refusals:    <count from journalctl, or "logging off">
```

Enable refusal logging while you are there:

```bash
sudo sed -i 's/^LOG_REFUSALS=0/LOG_REFUSALS=1/' /etc/claude-egress-guard.conf
```

## Phase 8 — Ongoing

| Event | Action |
| --- | --- |
| Package update | `sudo claude-egress-guard verify --deep` |
| Vendor update replaced the gated path | start `claude` once through a gated path to heal, then `verify --deep` |
| Exit moved | `sudo claude-egress-guard set-exit --ip NEW --country CC` |
| Repeated refusals | read `journalctl -t claude-egress-guard`; the proxy is unstable |
| Monthly | `verify --deep` + one real prompt + check the refusal count |
| Suspected bypass | `status`, then `cat /proc/<pid>/cgroup` for a `run-r...scope` |

## Phase 9 — Roll back

```bash
sudo claude-egress-guard uninstall      # restores the files it replaced
```

That removes the gate and the policy, and restores whatever was at each managed
path. It does not remove the client itself:

```bash
# vendor installer
rm -f ~/.local/bin/claude && rm -rf ~/.local/share/claude
# npm
npm uninstall -g @anthropic-ai/claude-code
# settings and session (destructive: deletes history and trust decisions)
rm -rf ~/.claude ~/.claude.json
```

## Stop conditions, collected

- The provider does not serve your region, or asks for material you cannot
  truthfully provide.
- The exit address moves during phase 2, or changes between phases.
- `verify --deep` reports a failed layer, or PATH resolves to an ungated binary.
- The drill does not recover.
- Anyone offers to share, rent or resell an account.

## How long it takes

Roughly 30-60 minutes of work plus waiting: host baseline and reboot, proxy
bring-up, client install, one browser round trip for login, and the drill. The
vendor install is faster than npm because it ships a single binary. Account
review, if any, is outside your control — do not build on top of an unverified
account.
