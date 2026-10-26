#!/usr/bin/env bash
# Self-test for claude-egress-guard. Runs entirely inside a throwaway prefix
# with fake curl / systemd-run / claude binaries. No root, no network.
set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
CLI="$HERE/claude-egress-guard"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ceg-test.XXXXXX")
PREFIX="$WORK/prefix"
BIN="$PREFIX/bin"
SRC="$WORK/src"
PASSED=0
FAILED=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

ok() {
	printf '  ok   %s\n' "$1"
	PASSED=$((PASSED + 1))
}
no() {
	printf '  FAIL %s\n' "$1"
	FAILED=$((FAILED + 1))
}

expect_rc() { # name expected actual
	if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (expected rc=$2, got rc=$3)"; fi
}

# ---------------------------------------------------------------------------
# fixtures: fake claude, fake curl, fake systemd-run
# ---------------------------------------------------------------------------
mkdir -p "$BIN" "$SRC" "$PREFIX/etc" "$PREFIX/usr/bin" "$PREFIX/usr/local/bin"

cat >"$SRC/claude" <<'EOF'
#!/bin/sh
printf 'REAL_CLAUDE'
for a in "$@"; do printf ' %s' "$a"; done
printf '\n'
EOF
chmod 0755 "$SRC/claude"

cat >"$BIN/curl" <<'EOF'
#!/bin/sh
# Emulates `curl -x PROXY URL` for the egress checker.
[ "${FAKE_CURL_FAIL:-0}" = "1" ] && exit 7
printf 'ip=%s\nloc=%s\nhttp=http/2\n' "${FAKE_IP:-203.0.113.10}" "${FAKE_LOC:-JP}"
EOF
chmod 0755 "$BIN/curl"

cat >"$BIN/systemd-run" <<'EOF'
#!/bin/bash
# Records the properties, then runs the command after `--`.
: >"${FAKE_SYSTEMD_LOG:-/dev/null}"
args=()
while [ $# -gt 0 ]; do
	case "$1" in
		--scope | --quiet | --collect) shift ;;
		-p)
			printf '%s\n' "$2" >>"${FAKE_SYSTEMD_LOG:-/dev/null}"
			shift 2
			;;
		--)
			shift
			break
			;;
		*) shift ;;
	esac
done
exec "$@"
EOF
chmod 0755 "$BIN/systemd-run"

# The gate demands root for the jail; pretend to be root inside the sandbox.
cat >"$BIN/id" <<'EOF'
#!/bin/sh
echo 0
EOF
chmod 0755 "$BIN/id"

export PATH="$BIN:$PATH"
export CEG_CURL="$BIN/curl"

# Pre-existing npm-style symlink that the installer must back up.
ln -sfn "$SRC/claude" "$PREFIX/usr/bin/claude"

# ---------------------------------------------------------------------------
printf 'install\n'
# ---------------------------------------------------------------------------
"$CLI" install --prefix "$PREFIX" --proxy http://127.0.0.1:1080 \
	--exit-ip 203.0.113.10 --country JP --real "$SRC/claude" --allow 100.64.0.0/10 \
	--dry-run >/dev/null 2>&1
expect_rc "dry-run exits 0" 0 $?
[ ! -e "$PREFIX/etc/claude-egress-guard.conf" ] && ok "dry-run writes nothing" || no "dry-run wrote the config"

"$CLI" install --prefix "$PREFIX" --proxy http://127.0.0.1:1080 \
	--exit-ip 203.0.113.10 --country JP --real "$SRC/claude" --allow 100.64.0.0/10 >/dev/null 2>&1
expect_rc "install exits 0" 0 $?

CONF="$PREFIX/etc/claude-egress-guard.conf"
[ -r "$CONF" ] && ok "config written" || no "config missing"
[ "$(stat -c '%a' "$CONF")" = "600" ] && ok "config mode 0600" || no "config mode is $(stat -c '%a' "$CONF")"
[ -x "$PREFIX/usr/local/bin/claude" ] && ok "gate installed" || no "gate missing"
[ -x "$PREFIX/usr/bin/claude" ] && ok "alt path installed" || no "alt path missing"
grep -q '^STRICT_NET=1' "$CONF" && ok "strict net defaults to on" || no "strict net not enabled"
grep -q '127.0.0.0/8' "$CONF" && ok "loopback allow-listed" || no "loopback missing from allow list"
grep -q '100.64.0.0/10' "$CONF" && ok "extra --allow honoured" || no "extra --allow missing"
[ -L "$PREFIX/opt/claude-real/claude" ] && ok "real binary pinned" || no "real binary not pinned"
BK=$(find "$PREFIX/var/lib/claude-egress-guard/backup" -name claude 2>/dev/null | head -n 1)
[ -n "$BK" ] && [ -L "$BK" ] && ok "original symlink backed up" || no "no backup of the original symlink"

# ---------------------------------------------------------------------------
printf 'gate behaviour\n'
# ---------------------------------------------------------------------------
run_gate() { CEG_CONF="$CONF" "$PREFIX/usr/local/bin/claude" "$@"; }

OUT=$(FAKE_IP=203.0.113.10 run_gate --print-config 2>&1)
expect_rc "gate starts with the expected exit" 0 $?
case "$OUT" in
	REAL_CLAUDE*) ok "gate execs the real binary" ;;
	*) no "gate did not exec the real binary: $OUT" ;;
esac

OUT=$(CEG_CONF="$CONF" "$PREFIX/usr/local/bin/claude" --version 2>&1)
expect_rc "--version passthrough" 0 $?
case "$OUT" in
	REAL_CLAUDE*) ok "--version skips the egress check" ;;
	*) no "--version did not reach the real binary" ;;
esac

FAKE_IP=198.51.100.7 run_gate --print-config >/dev/null 2>&1
expect_rc "gate refuses on exit mismatch" 77 $?

FAKE_LOC=US run_gate --print-config >/dev/null 2>&1
expect_rc "gate refuses on wrong country" 77 $?

FAKE_CURL_FAIL=1 run_gate --print-config >/dev/null 2>&1
expect_rc "gate refuses when the proxy is unreachable" 77 $?

CEG_CONF="$WORK/missing.conf" "$PREFIX/usr/local/bin/claude" --print-config >/dev/null 2>&1
expect_rc "gate refuses without config" 77 $?

# ---------------------------------------------------------------------------
printf 'self-heal\n'
# ---------------------------------------------------------------------------
ln -sfn "$SRC/claude" "$PREFIX/usr/bin/claude" # simulate an npm update
FAKE_IP=203.0.113.10 run_gate --print-config >/dev/null 2>&1
if head -c 200 "$PREFIX/usr/bin/claude" | grep -q claude-egress-guard; then
	ok "alt path restored to the gate after an update"
else
	no "alt path was not restored"
fi

# ---------------------------------------------------------------------------
printf 'strict jail\n'
# ---------------------------------------------------------------------------
: >"$WORK/systemd.log"
FAKE_IP=203.0.113.10 FAKE_SYSTEMD_LOG="$WORK/systemd.log" run_gate --print-config >/dev/null 2>&1
expect_rc "gate runs inside the scope" 0 $?
grep -q 'IPAddressDeny=any' "$WORK/systemd.log" && ok "jail denies by default" || no "IPAddressDeny missing"
grep -q 'IPAddressAllow=.*127.0.0.0/8' "$WORK/systemd.log" && ok "jail allow list forwarded" || no "IPAddressAllow malformed"

# ---------------------------------------------------------------------------
printf 'set-exit / refusal logging\n'
# ---------------------------------------------------------------------------
FAKE_IP=198.51.100.9 "$CLI" set-exit --prefix "$PREFIX" --ip 198.51.100.9 >/dev/null 2>&1
expect_rc "set-exit accepts an address the proxy serves" 0 $?
grep -q 'EXPECTED_IP="198.51.100.9"' "$CONF" && ok "policy rewritten" || no "policy not rewritten"

FAKE_IP=203.0.113.10 "$CLI" set-exit --prefix "$PREFIX" --ip 192.0.2.77 >/dev/null 2>&1
expect_rc "set-exit refuses an address the proxy does not serve" 1 $?
grep -q 'EXPECTED_IP="198.51.100.9"' "$CONF" && ok "policy untouched after a refusal" || no "policy changed on a failed set-exit"

FAKE_IP=203.0.113.10 "$CLI" set-exit --prefix "$PREFIX" --ip 203.0.113.10 >/dev/null 2>&1
expect_rc "set-exit returns to the original exit" 0 $?

cat >"$BIN/logger" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${FAKE_LOGGER_LOG:-/dev/null}"
EOF
chmod 0755 "$BIN/logger"

sed -i 's/^LOG_REFUSALS=0/LOG_REFUSALS=1/' "$CONF"
: >"$WORK/logger.log"
FAKE_IP=198.51.100.7 FAKE_LOGGER_LOG="$WORK/logger.log" run_gate --print-config >/dev/null 2>&1
expect_rc "refusal still exits 77 with logging on" 77 $?
grep -q 'refused:' "$WORK/logger.log" && ok "refusal written to the journald target" || no "refusal not logged"
sed -i 's/^LOG_REFUSALS=1/LOG_REFUSALS=0/' "$CONF"

# ---------------------------------------------------------------------------
printf 'preflight\n'
# ---------------------------------------------------------------------------
"$CLI" preflight --json >"$WORK/pf.json" 2>/dev/null
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["checks"] and isinstance(d["blockers"], int)' \
	"$WORK/pf.json" 2>/dev/null && ok "preflight emits valid JSON" || no "preflight JSON invalid"
"$CLI" preflight >/dev/null 2>&1
pf_rc=$?
if [ "$pf_rc" -eq 0 ] || [ "$pf_rc" -eq 1 ]; then
	ok "preflight exits 0 or 1 (got $pf_rc)"
else
	no "preflight returned rc=$pf_rc"
fi

# ---------------------------------------------------------------------------
printf 'verify / status / uninstall\n'
# ---------------------------------------------------------------------------
FAKE_IP=203.0.113.10 "$CLI" verify --prefix "$PREFIX" >/dev/null 2>&1
expect_rc "verify passes when everything is wired" 0 $?

FAKE_IP=198.51.100.7 "$CLI" verify --prefix "$PREFIX" >/dev/null 2>&1
expect_rc "verify fails on exit mismatch" 1 $?

"$CLI" status --prefix "$PREFIX" >/dev/null 2>&1
expect_rc "status exits 0" 0 $?

"$CLI" uninstall --prefix "$PREFIX" >/dev/null 2>&1
expect_rc "uninstall exits 0" 0 $?
[ -L "$PREFIX/usr/bin/claude" ] && ok "original alt symlink restored" || no "alt symlink not restored"
[ ! -e "$CONF" ] && ok "config removed" || no "config left behind"
[ ! -e "$PREFIX/usr/local/bin/claude" ] && ok "gate removed" || no "gate left behind"

# ---------------------------------------------------------------------------
printf 'installer\n'
# ---------------------------------------------------------------------------
ROOT=$(CDPATH='' cd -- "$HERE/../../.." && pwd -P)
if [ -f "$ROOT/install.sh" ]; then
	"$ROOT/install.sh" --help >/dev/null 2>&1
	expect_rc "install.sh --help" 0 $?
	"$ROOT/install.sh" --skill-only --dest "$WORK/skills" >/dev/null 2>&1
	expect_rc "install.sh --skill-only" 0 $?
	[ -f "$WORK/skills/claude-egress-guard/SKILL.md" ] && ok "skill copied to the target directory" || no "skill not copied"
	"$ROOT/install.sh" --proxy http://127.0.0.1:1080 >/dev/null 2>&1
	expect_rc "install.sh refuses a missing --exit-ip" 1 $?
else
	printf '  skip install.sh (not a checkout)\n'
fi

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
