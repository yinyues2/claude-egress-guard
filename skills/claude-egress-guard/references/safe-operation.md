# Safe operation baseline

The gate decides where traffic leaves. This file decides everything else that
makes a Claude Code deployment safe to keep running: credentials, client
settings, secrets, backups, monitoring and what to do when something looks wrong.

It applies after `references/zero-to-deployed.md` has taken you to a working,
gated host.

## 1. Credentials

- `~/.claude/.credentials.json` is a **session**, not a config file. Mode 600,
  owned by the account that runs Claude. Never copy it to another machine, never
  put it in a backup that leaves the host.
- Re-login is the rotation mechanism. If the file may have leaked: `claude auth
  logout`, sign out the other sessions from the provider's account page, log in
  again, then check usage for anything you do not recognise.
- Login codes are single use and short lived. Do not paste them into a chat, a
  ticket, a log or a shell history. If an orchestrator passes one through stdin,
  it must not echo it.
- Never store a provider token in `CLAUDE.md`, `settings.json`, a git remote URL
  or a shell profile.

## 2. Client settings

The gate owns egress. The client must not have a second opinion:

- **No proxy in `~/.claude/settings.json`.** A value there can win over the
  environment the gate exports, which is the quietest way to send traffic around
  the gate.
- **Keep permission prompts on** unless the directory is a throwaway sandbox.
  A blanket "allow everything" setting turns every prompt injection into a shell.
- **Review hooks and MCP servers before enabling them.** Both execute code with
  your privileges; a hook added for convenience is a startup script with your
  keys in scope.
- **One installation.** `npx`, a second global install, or a wrapper that calls
  the real binary are ungated paths. Remove them or accept that the gate does not
  cover them.

## 3. Secrets in the working tree

- Keep API keys in a `.env` with mode 600, or in a secret manager. Not in
  `CLAUDE.md`, not in committed examples, not in prompts.
- Add `.env`, `*.pem`, `*.key` and `credentials*` to `.gitignore` before the first
  commit, not after the first leak.
- `~/.claude/` and the project's `.claude/` should not be world-readable:
  `chmod 700 ~/.claude`, `chmod -R go-rwx .claude` where it exists.
- When you paste logs into an issue, strip addresses, tokens, account identifiers
  and full config files. Documentation ranges (`203.0.113.0/24`) exist for this.

## 4. Working directory and blast radius

- Run Claude in a dedicated directory, not `/` and not your home root. A
  mistaken `rm` or a wide refactor should hit a project, not a system.
- Keep the project under git. Review diffs before accepting bulk edits; a clean
  `git diff` is the cheapest safety net there is.
- Do not run unattended, long-lived agents against production credentials. If you
  must, give them a scoped token and a directory they cannot escape.
- Snapshot before large changes (`git stash`, a tarball, a provider snapshot).

## 5. Monitoring

- `LOG_REFUSALS=1` turns "did it ever refuse?" into `journalctl -t
  claude-egress-guard`. Check it weekly; a burst of refusals means the proxy is
  unstable, not that the gate is broken.
- After every package update: `claude-egress-guard verify --deep`. The self-heal
  is best effort, verification is proof.
- Keep a one-line change log for policy edits (who changed `EXPECTED_IP`,
  `ALLOW_IPS` or `STRICT_NET`, and why). Six months later this is the only thing
  that explains an incident.
- Record the version you are on. `claude --version`, `claude-egress-guard status`.

## 6. Incident response

Match the symptom, then act in order. Stop the bleeding before you investigate.

### Exit changed or a leak is suspected

1. Stop new sessions; let running ones finish or kill them deliberately.
2. Confirm the current exit: `claude-egress-guard status`, then a trace through
   the proxy.
3. If the proxy moved, `set-exit --ip NEW --country CC`; if it is dead, leave the
   gate refusing. A refusing gate is working correctly.
4. Read `journalctl -t claude-egress-guard` for when refusals started.
5. Only then review IP history and decide whether the provider needs to hear
   from you.

### The provider asks for verification, or the session is signed out

1. Do not retry from a different address. Address hopping during a review is the
   worst possible signal.
2. Stop automation that would keep opening sessions.
3. Follow the provider's instructions truthfully, or stop and reassess
   eligibility. Never supply documents or numbers that are not yours.
4. Preserve logs and the deployment record; do not delete evidence.

### A credential may have leaked

1. `claude auth logout` on the host.
2. Revoke sessions from the provider's account page.
3. Re-login through the gate, then `verify --deep`.
4. Check usage and recent activity for anything you cannot explain.
5. Fix the path it leaked through (git history, a pasted log, a world-readable
   file) before moving on.

### A bypass is suspected

1. `claude-egress-guard status` — is the gate still installed at both paths?
2. `npx`, a second install, a wrapper, a container: list every way `claude` can
   start on that host.
3. For a running process, `cat /proc/<pid>/cgroup` should show a `run-r...scope`
   when `STRICT_NET=1`. If it does not, that process did not come through the
   gate.
4. Fix the entry point, then drill again.

## 7. Update discipline

| Change | Follow-up |
| --- | --- |
| Claude Code update | `verify --deep`, one real prompt |
| OS upgrade | re-check systemd version, IPv6 setting, DNS resolvers, then `verify --deep` |
| Proxy change | `set-exit`, then `verify` |
| Policy change | record it, then `verify --deep` |
| Host rebuild | follow `zero-to-deployed.md` from phase 1; do not copy credentials |

## 8. What stays out of scope

Account registration, payment, identity verification, and anything that would
misrepresent who you are or where you are. Those are the operator's, permanently.
