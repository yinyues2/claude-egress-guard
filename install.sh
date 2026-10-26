#!/usr/bin/env bash
# claude-egress-guard — one-shot installer.
#
# From a checkout:   sudo ./install.sh --proxy URL --exit-ip ADDR
# From the network:  curl -fsSL https://github.com/yinyues2/claude-egress-guard/raw/main/install.sh \
#                      | sudo bash -s -- --proxy URL --exit-ip ADDR
#
# The script downloads a pinned release tarball when it is not run from a
# checkout, verifies the expected layout, then hands over to the project CLI.
# It never edits system files itself.
set -u

REPO="yinyues2/claude-egress-guard"
PINNED_REF="v1.1.0"
SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
WORK=""

cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

say() { printf '%s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; }
die() {
	err "$*"
	exit 1
}

usage() {
	cat <<'EOF'
claude-egress-guard installer

USAGE
  install.sh --proxy URL --exit-ip ADDR [options]
  install.sh --skill-only [--dest DIR]
  install.sh --uninstall [--prefix DIR]

OPTIONS
  --proxy URL        local HTTP/mixed proxy endpoint (required to install)
  --exit-ip ADDR     public IPv4 the proxy must exit from (required)
  --country CC       two-letter country to enforce (optional)
  --allow LIST       extra CIDRs inside the kernel jail, comma separated
  --strict-net MODE  on|off kernel jail (default on)
  --prefix DIR       install under DIR instead of / (testing)
  --ref REF          release tag or branch to download (default: v1.1.0)
  --dry-run          show the install plan only
  --yes              do not prompt
  --skill-only       copy the agent skill into a skills directory instead
  --dest DIR         target for --skill-only (default: ~/.hermes/skills)
  --uninstall        remove the gate and restore the previous files
  -h, --help         this text

NOTES
  The installer needs root for a real install because the gate writes to
  /usr/local and /etc. --prefix works unprivileged and is what the test suite
  uses. Nothing on the host is modified before the CLI prints its plan.
EOF
}

PROXY=""
EXIT_IP=""
COUNTRY=""
ALLOW=""
STRICT=""
PREFIX=""
REF="$PINNED_REF"
DRY="0"
ASSUME_YES="0"
SKILL_ONLY="0"
DEST="${HOME}/.hermes/skills"
UNINSTALL="0"

while [ $# -gt 0 ]; do
	case "$1" in
		--proxy) PROXY="${2:-}"; shift 2 ;;
		--exit-ip) EXIT_IP="${2:-}"; shift 2 ;;
		--country) COUNTRY="${2:-}"; shift 2 ;;
		--allow) ALLOW="${2:-}"; shift 2 ;;
		--strict-net) STRICT="${2:-}"; shift 2 ;;
		--prefix) PREFIX="${2:-}"; shift 2 ;;
		--ref) REF="${2:-}"; shift 2 ;;
		--dry-run) DRY="1"; shift ;;
		--yes | -y) ASSUME_YES="1"; shift ;;
		--skill-only) SKILL_ONLY="1"; shift ;;
		--dest) DEST="${2:-}"; shift 2 ;;
		--uninstall) UNINSTALL="1"; shift ;;
		-h | --help) usage; exit 0 ;;
		*) die "unknown option: $1 (try --help)" ;;
	esac
done

# ---------------------------------------------------------------------------
# Locate the project: a checkout next to this script, or a downloaded tarball.
# ---------------------------------------------------------------------------
project_root() {
	if [ -x "$SELF_DIR/skills/claude-egress-guard/scripts/claude-egress-guard" ]; then
		printf '%s\n' "$SELF_DIR"
		return 0
	fi
	command -v curl >/dev/null 2>&1 || die "curl is required to download the project"
	command -v tar >/dev/null 2>&1 || die "tar is required to unpack the project"
	WORK=$(mktemp -d "${TMPDIR:-/tmp}/ceg-install.XXXXXX") || die "cannot create a temp dir"
	local url
	case "$REF" in
		main | master | [0-9]*) url="https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF" ;;
		*) url="https://codeload.github.com/$REPO/tar.gz/refs/tags/$REF" ;;
	esac
	say "downloading $REPO@$REF"
	curl -fsSL --max-time 120 --retry 2 "$url" -o "$WORK/src.tar.gz" ||
		die "download failed: $url"
	tar -xzf "$WORK/src.tar.gz" -C "$WORK" || die "cannot unpack the release tarball"
	local root
	root=$(find "$WORK" -maxdepth 1 -mindepth 1 -type d -name 'claude-egress-guard-*' | head -n 1)
	[ -n "$root" ] || die "unexpected archive layout"
	[ -x "$root/skills/claude-egress-guard/scripts/claude-egress-guard" ] ||
		die "archive does not contain the expected scripts"
	printf '%s\n' "$root"
}

confirm() {
	[ "$ASSUME_YES" = "1" ] && return 0
	if [ -r /dev/tty ]; then
		local answer=""
		printf '%s [y/N] ' "$1" >/dev/tty
		read -r answer </dev/tty || answer=""
		case "$answer" in
			y | Y | yes | YES) return 0 ;;
			*) die "aborted" ;;
		esac
	fi
	die "no terminal for confirmation; re-run with --yes"
}

# ---------------------------------------------------------------------------
# --skill-only: copy the skill into an agent's skills directory.
# ---------------------------------------------------------------------------
if [ "$SKILL_ONLY" = "1" ]; then
	root=$(project_root)
	mkdir -p "$DEST" || die "cannot create $DEST"
	rm -rf "${DEST:?}/claude-egress-guard"
	cp -R "$root/skills/claude-egress-guard" "$DEST/" || die "copy failed"
	say "skill installed: $DEST/claude-egress-guard"
	say "ask your agent to load the 'claude-egress-guard' skill and follow SKILL.md"
	exit 0
fi

# ---------------------------------------------------------------------------
# --uninstall
# ---------------------------------------------------------------------------
if [ "$UNINSTALL" = "1" ]; then
	cli=""
	if [ -n "$PREFIX" ]; then
		[ -x "$PREFIX/usr/local/sbin/claude-egress-guard" ] && cli="$PREFIX/usr/local/sbin/claude-egress-guard"
	else
		[ -x /usr/local/sbin/claude-egress-guard ] && cli="/usr/local/sbin/claude-egress-guard"
	fi
	if [ -z "$cli" ]; then
		root=$(project_root)
		cli="$root/skills/claude-egress-guard/scripts/claude-egress-guard"
	fi
	confirm "Remove the gate and restore the previous binaries?"
	if [ -n "$PREFIX" ]; then
		exec "$cli" uninstall --prefix "$PREFIX"
	fi
	exec "$cli" uninstall
fi

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------
[ -n "$PROXY" ] || die "--proxy is required (try --help)"
[ -n "$EXIT_IP" ] || die "--exit-ip is required (try --help)"
case "$PROXY" in
	http://* | https://*) ;;
	*) die "--proxy must start with http:// or https://" ;;
esac

if [ -z "$PREFIX" ] && [ "$(id -u)" -ne 0 ]; then
	die "a real install needs root; re-run with sudo, or use --prefix for a sandbox"
fi

root=$(project_root)
cli="$root/skills/claude-egress-guard/scripts/claude-egress-guard"

args=(install --proxy "$PROXY" --exit-ip "$EXIT_IP")
[ -n "$COUNTRY" ] && args+=(--country "$COUNTRY")
[ -n "$ALLOW" ] && args+=(--allow "$ALLOW")
[ -n "$STRICT" ] && args+=(--strict-net "$STRICT")
[ -n "$PREFIX" ] && args+=(--prefix "$PREFIX")
[ "$DRY" = "1" ] && args+=(--dry-run)

"$cli" "${args[@]}" || die "install failed"

if [ "$DRY" = "1" ]; then
	say "dry run only; re-run without --dry-run to apply"
	exit 0
fi

say ""
say "running verify --deep ..."
if [ -n "$PREFIX" ]; then
	"$cli" verify --deep --prefix "$PREFIX" || die "verify failed - do not use the gate until it passes"
else
	"$cli" verify --deep || die "verify failed - do not use the gate until it passes"
fi

say ""
say "installed. next:"
say "  claude-egress-guard status"
say "  claude-egress-guard drill --service <your-proxy-unit>"
say "  journalctl -t claude-egress-guard -f      # when LOG_REFUSALS=1"
