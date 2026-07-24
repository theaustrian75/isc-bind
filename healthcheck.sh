#!/bin/sh
# Probe named with dig (Do53). Prefer this over a bare pid check: the server must answer.
#
# Env (optional):
#   BIND_HEALTHCHECK_SERVER  default 127.0.0.1
#   BIND_HEALTHCHECK_PORT    default 53
#   BIND_HEALTHCHECK_QNAME   default hostname.bind (CHAOS TXT — answered by default)
#   BIND_HEALTHCHECK_QTYPE   default TXT
#   BIND_HEALTHCHECK_CLASS   default CH
set -eu

pidof named >/dev/null || exit 1

SERVER="${BIND_HEALTHCHECK_SERVER:-127.0.0.1}"
PORT="${BIND_HEALTHCHECK_PORT:-53}"
QNAME="${BIND_HEALTHCHECK_QNAME:-hostname.bind}"
QTYPE="${BIND_HEALTHCHECK_QTYPE:-TXT}"
QCLASS="${BIND_HEALTHCHECK_CLASS:-CH}"

dig +time=2 +tries=1 +norecurse -p "$PORT" @"$SERVER" "$QNAME" "$QTYPE" "$QCLASS" >/dev/null || exit 1
exit 0
