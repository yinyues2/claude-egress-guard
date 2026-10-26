#!/usr/bin/env bash
# claude-egress-guard — fail-closed launcher for Claude Code.
#
# Installed as <prefix>/usr/local/bin/claude and mirrored to <prefix>/usr/bin/claude.
# Every policy value lives in /etc/claude-egress-guard.conf. If the config is
# missing, the egress check fails, or the strict network jail cannot be applied,
# this script refuses to start Claude at all.
#
# Exit codes: 77 = refused by the gate, 78 = config problem.
set -u

MARKER="claude-egress-guard"
CONF="${CEG_CONF:-/etc/claude-egress-guard.conf}"
REFUSE=77

refuse() {
	printf 'claude-egress-guard: %s\n' "$*" >&2
	exit "$REFUSE"
}

[ -r "$CONF" ] || refuse "missing or unreadable $CONF - refusing to start"
# shellcheck source=/dev/null
. "$CONF" || refuse "cannot load $CONF - refusing to start"
# The checker must read the same policy file, whatever the entry point was.
export CEG_CONF="$CONF"

for _var in CHECK_BIN REAL_BIN PROXY EXPECTED_IP; do
	[ -n "${!_var:-}" ] || refuse "config value $_var is empty in $CONF"
done
unset _var

# Checked before every diagnostic path too, so a broken pin reports the real
# reason instead of "command not found" from exec.
[ -x "$REAL_BIN" ] || refuse "real Claude binary missing or not executable: $REAL_BIN"

# ---------------------------------------------------------------------------
# 1. Diagnostic paths that must never depend on the network.
# ---------------------------------------------------------------------------
case "${1:-}" in
	--ceg-check)
		# Gate self-test used by drift checks and drill scripts.
		exec "$CHECK_BIN"
		;;
	--version | -v | --help | -h)
		exec "$REAL_BIN" "$@"
		;;
esac

# ---------------------------------------------------------------------------
# 2. Self-heal: package updates rewrite the /usr/bin symlink back to the real
#    binary. Restore the gate copy so absolute-path callers stay covered.
# ---------------------------------------------------------------------------
ALT="${ALT_PATH:-}"
if [ -n "$ALT" ]; then
	SELF_REAL=$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")
	ALT_REAL=$(readlink -f -- "$ALT" 2>/dev/null || printf '%s' "$ALT")
	if [ "$SELF_REAL" != "$ALT_REAL" ] && [ -w "$(dirname -- "$ALT")" ]; then
		if ! head -c 200 -- "$ALT" 2>/dev/null | grep -q -- "$MARKER"; then
			# rm first: cp through an npm symlink would overwrite the real binary.
			rm -f -- "$ALT" 2>/dev/null || true
			install -m 0755 -- "$0" "$ALT" 2>/dev/null || true
		fi
	fi
fi

# ---------------------------------------------------------------------------
# 3. Egress check. Runs before every start; failure is fatal, never a warning.
# ---------------------------------------------------------------------------
if [ ! -x "$CHECK_BIN" ]; then
	refuse "egress checker missing or not executable: $CHECK_BIN"
fi
if ! CHECK_OUT=$("$CHECK_BIN" 2>&1); then
	printf '%s\n' "$CHECK_OUT" >&2
	refuse "egress check failed - refusing to start (fail-closed)"
fi

# ---------------------------------------------------------------------------
# 4. Proxy environment for the client itself and every child process.
# ---------------------------------------------------------------------------
export ALL_PROXY="$PROXY" all_proxy="$PROXY"
export http_proxy="$PROXY" https_proxy="$PROXY"
export HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY"
export NO_PROXY="127.0.0.1,localhost,::1" no_proxy="127.0.0.1,localhost,::1"

# ---------------------------------------------------------------------------
# 5. Optional kernel-level jail: only loopback, the proxy upstream and the
#    allow-listed networks are reachable from the whole Claude process tree.
# ---------------------------------------------------------------------------
case "${STRICT_NET:-0}" in
	1 | yes | true)
		[ -n "${ALLOW_IPS:-}" ] || refuse "STRICT_NET is on but ALLOW_IPS is empty"
		command -v systemd-run >/dev/null 2>&1 || refuse "STRICT_NET is on but systemd-run is unavailable"
		[ "$(id -u)" -eq 0 ] || refuse "STRICT_NET is on but this process is not root"
		exec systemd-run --scope --quiet --collect \
			-p IPAddressDeny=any \
			-p "IPAddressAllow=$ALLOW_IPS" \
			-- "$REAL_BIN" "$@"
		;;
esac

exec "$REAL_BIN" "$@"
