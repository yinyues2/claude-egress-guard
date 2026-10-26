#!/usr/bin/env bash
# claude-egress-guard — verify that the configured proxy really exits through
# the expected address and country.
#
# Prints one line on stdout:
#   ok exit=<address> country=<cc>
#   fail reason=<why> [detail=...]
# Never writes state, never retries, never falls back to a direct connection.
set -u

CONF="${CEG_CONF:-/etc/claude-egress-guard.conf}"
[ -r "$CONF" ] || { echo "fail reason=config_missing"; exit 1; }
# shellcheck source=/dev/null
. "$CONF" || { echo "fail reason=config_unreadable"; exit 1; }

: "${PROXY:?}" 2>/dev/null || { echo "fail reason=proxy_missing"; exit 1; }
: "${EXPECTED_IP:?}" 2>/dev/null || { echo "fail reason=expected_ip_missing"; exit 1; }

TIMEOUT="${CHECK_TIMEOUT:-6}"
TRACE_URL="${TRACE_URL:-https://www.cloudflare.com/cdn-cgi/trace}"
FALLBACK_URL="${FALLBACK_URL:-https://ipinfo.io/json}"
CURL_BIN="${CEG_CURL:-curl}"

fetch() {
	# -4 keeps the probe itself on IPv4; -f turns HTTP errors into failures.
	"$CURL_BIN" -4 -fsS --max-time "$TIMEOUT" -x "$PROXY" "$1" 2>/dev/null
}

BODY=$(fetch "$TRACE_URL")
IP=$(printf '%s\n' "$BODY" | sed -n 's/^ip=//p' | head -n 1)
COUNTRY=$(printf '%s\n' "$BODY" | sed -n 's/^loc=//p' | head -n 1)

if [ -z "$IP" ]; then
	BODY=$(fetch "$FALLBACK_URL")
	IP=$(printf '%s' "$BODY" | sed -n 's/.*"ip":[[:space:]]*"\([^"]*\)".*/\1/p')
	COUNTRY=$(printf '%s' "$BODY" | sed -n 's/.*"country":[[:space:]]*"\([^"]*\)".*/\1/p')
fi

[ -n "$IP" ] || { echo "fail reason=proxy_unreachable"; exit 1; }
[ "$IP" = "$EXPECTED_IP" ] || { echo "fail reason=exit_ip_mismatch exit=$IP"; exit 1; }

EXPECTED_COUNTRY="${EXPECTED_COUNTRY:-}"
if [ -n "$EXPECTED_COUNTRY" ] && [ "$COUNTRY" != "$EXPECTED_COUNTRY" ]; then
	echo "fail reason=country_mismatch country=${COUNTRY:-unknown}"
	exit 1
fi

echo "ok exit=$IP country=${COUNTRY:-unknown}"
exit 0
