# Zero to deployed

For a host that has never run Claude Code and an operator who has never had an
account. Every phase below states who does it, what to run, the checkpoint that
ends the phase, and the conditions that mean **stop**.

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

Target: a fresh Linux VPS you control. Debian 12/13 or Ubuntu 22.04/24.04,
2 vCPU, 2 GB RAM, 20 GB disk, root access.

```bash
# 1. updates and time
apt-get update && apt-get -y upgrade
timedatectl set-timezone <Your/Real_Timezone>     # your real location, not a costume
timedatectl set-ntp true && timedatectl status

# 2. free space for npm, logs and backups (needs 2 GB+)
df -h /var

# 3. optional but recommended on a single-stack host: remove IPv6 ambiguity
printf 'net.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1\n' \
  > /etc/sysctl.d/99-disable-ipv6.conf
sysctl --system
```

Checkpoint: clock synchronised, timezone is where you actually are, `/var` has
2 GB free.

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
2. Prove the exit, three times, ten minutes apart:

   ```bash
   for i in 1 2 3; do
     curl -4 -fsS --max-time 8 -x http://127.0.0.1:1080 \
       https://www.cloudflare.com/cdn-cgi/trace | grep -E '^(ip|loc)='
     sleep 600
   done
   ```

3. Decide the allow list now:

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

## Phase 3 — Install Claude Code, do not launch it

```bash
# npm path (needs Node 18+; install a current LTS first if absent)
npm i -g @anthropic-ai/claude-code
command -v claude && readlink -f "$(command -v claude)"
claude --version
```

Do **not** run `claude` yet. Starting it now would open the login flow before the
gate exists, which is the exact situation this project is meant to prevent.

Checkpoint: `claude --version` prints a version and the resolved binary lives
under the npm prefix (or the native installer's directory).

## Phase 4 — Install the gate, prove it

```bash
curl -fsSL https://raw.githubusercontent.com/yinyues2/claude-egress-guard/main/install.sh \
  | sudo bash -s -- --proxy http://127.0.0.1:1080 --exit-ip <ADDR> --country <CC>
```

The installer ends with `verify --deep`, which must print `0 check(s) failed`.
Then drill the failure path:

```bash
sudo claude-egress-guard drill --service <your-proxy-unit>
```

Checkpoint: `verify --deep` clean, drill reports `PASS gate refused to start with
the proxy down` and `PASS gate recovered after Ns`.

Stop if any layer fails. Do not log in through a gate that has not proven itself:
the first login is the most valuable traffic you will ever send.

## Phase 5 — First login, through the gate

Run the client on the host and complete the flow in your own browser:

```bash
claude auth login
```

- The CLI prints a URL. Open it in the browser that is already signed in to your
  account, approve, and copy the code back. Codes are single use and expire in
  minutes.
- If the host has no terminal for you, an orchestrator can pass the code through
  stdin; the code must never be written to a log, a chat transcript or a file.
- Credentials land in `~/.claude/.credentials.json` (mode 600). Do not copy that
  file between machines: it is a session, not a configuration.

Checkpoint:

```bash
claude auth status
claude -p 'Reply with exactly: OK'   # costs a request; ask before running
```

Stop if the exit changed between phase 2 and now: re-run `verify` and
`set-exit` first.

## Phase 6 — First-run settings

- **Do not put a proxy in `~/.claude/settings.json`.** The gate owns egress; a
  second value inside the client is the fastest way to send traffic around it.
- Keep auto-update on, and re-run `verify --deep` after every update.
- Set `permissions` deliberately for the work this host does; the default
  prompt-per-tool behaviour is the safer starting point.
- Do not enable a second Claude installation, an `npx` alias, or a wrapper that
  calls the real binary — each one is an ungated path.

## Phase 7 — Record the evidence

Write this down next to the deployment (not in a public file):

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
| Exit moved | `sudo claude-egress-guard set-exit --ip NEW --country CC` |
| Repeated refusals | read `journalctl -t claude-egress-guard`; the proxy is unstable |
| Monthly | `verify --deep` + one real prompt + check the refusal count |
| Suspected bypass | `status`, then `cat /proc/<pid>/cgroup` for a `run-r...scope` |

## Stop conditions, collected

- The provider does not serve your region, or asks for material you cannot
  truthfully provide.
- The exit address moves during phase 2, or changes between phases.
- `verify --deep` reports a failed layer.
- The drill does not recover.
- Anyone offers to share, rent or resell an account.

## How long it takes

Roughly 60-90 minutes of work plus waiting: DNS and proxy bring-up, npm install,
one browser round trip for login, and the drill. Account review, if any, is
outside your control — do not build on top of an unverified account.
