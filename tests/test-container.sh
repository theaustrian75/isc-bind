#!/bin/sh
# Build-independent container smoke tests. Pass the image reference.
# Usage: tests/test-container.sh IMAGE
set -eu

IMAGE="${1:?Usage: tests/test-container.sh IMAGE}"
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
CONTAINER="isc-bind-bind9-test-$$"
TMP_ROOT=$(mktemp -d)
RUNTIME_UID=12345
RUNTIME_GID=12346

# Invoked through trap.
# shellcheck disable=SC2317
cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

echo "==> Smoke-testing $IMAGE (bind9)"

docker run --rm --entrypoint /bin/sh "$IMAGE" -c \
  'test -x /usr/local/bin/entrypoint.sh && test -x /usr/local/bin/healthcheck.sh'

docker run --rm --entrypoint /bin/sh "$IMAGE" -c \
  'apk info -e bind bind-tools'

version=$(docker run --rm --entrypoint /usr/sbin/named "$IMAGE" -v 2>&1 || true)
if [ -z "$version" ]; then
  echo "ERROR: named produced no version output" >&2
  exit 1
fi
echo "    version: $version"

default_settings=$(docker run --rm --entrypoint /bin/sh "$IMAGE" \
  -c 'printf "%s:%s %s" "$BIND_UID" "$BIND_GID" "$TZ"')
if [ "$default_settings" != "20002:20002 UTC" ]; then
  echo "Expected defaults '20002:20002 UTC', got '$default_settings'" >&2
  exit 1
fi

docker image inspect "$IMAGE" |
  jq -e '.[0].Config.Healthcheck.Test == ["CMD", "/usr/local/bin/healthcheck.sh"]' >/dev/null

# Public DNSKEY trust anchors may ship as *.key (bind-dnssec-root); only fail on
# private material that must never be baked into the image.
if docker run --rm --entrypoint /bin/sh "$IMAGE" -c \
  'find / \( -name "*.private" -o -name "rndc.key" -o -name "session.key" -o -name "*.p12" -o -name "*.pfx" \) 2>/dev/null | grep -q .'; then
  echo "ERROR: private key / control-channel material found inside image" >&2
  exit 1
fi

assert_failure() {
  expected=$1
  shift
  if output=$("$@" 2>&1); then
    echo "Expected command to fail: $*" >&2
    exit 1
  fi
  case "$output" in
    *"$expected"*) ;;
    *)
      printf 'Expected failure containing %s, got:\n%s\n' "$expected" "$output" >&2
      exit 1
      ;;
  esac
}

assert_failure "Required configuration file is missing" \
  docker run --rm "$IMAGE"

assert_failure "BIND_UID must be a non-zero numeric ID" \
  docker run --rm -e BIND_UID=0 \
  -v "$ROOT/tests/fixtures/named.conf:/etc/bind/named.conf:ro" "$IMAGE"

assert_failure "BIND_GID must be a non-zero numeric ID" \
  docker run --rm -e BIND_GID=abc \
  -v "$ROOT/tests/fixtures/named.conf:/etc/bind/named.conf:ro" "$IMAGE"

assert_failure "TZ must be an installed IANA timezone" \
  docker run --rm -e 'TZ=America/New York' \
  -v "$ROOT/tests/fixtures/named.conf:/etc/bind/named.conf:ro" "$IMAGE"

mkdir -p "$TMP_ROOT/etc" "$TMP_ROOT/certs"
cp "$ROOT/tests/fixtures/named.conf" "$TMP_ROOT/etc/named.conf"
chmod 755 "$TMP_ROOT" "$TMP_ROOT/etc" "$TMP_ROOT/certs"
chmod 644 "$TMP_ROOT/etc/named.conf"

# no-new-privileges omitted: ambient NET_BIND_SERVICE after setpriv uid drop.
docker run -d --name "$CONTAINER" \
  --read-only \
  --cap-drop ALL \
  --cap-add CHOWN \
  --cap-add SETUID \
  --cap-add SETGID \
  --cap-add DAC_OVERRIDE \
  --cap-add NET_BIND_SERVICE \
  --pids-limit 128 \
  --memory 256m \
  -e BIND_UID="$RUNTIME_UID" \
  -e BIND_GID="$RUNTIME_GID" \
  -e TZ=UTC \
  -v "$TMP_ROOT/etc:/etc/bind:ro" \
  -v "$TMP_ROOT/certs:/etc/bind/certs:ro" \
  --tmpfs /run/named:rw,mode=0750,size=16m,uid="$RUNTIME_UID",gid="$RUNTIME_GID" \
  --tmpfs /tmp:rw,mode=1777,size=16m \
  --tmpfs /var/cache/bind:rw,mode=0755,size=32m,uid="$RUNTIME_UID",gid="$RUNTIME_GID" \
  --tmpfs /var/lib/bind:rw,mode=0755,size=32m,uid="$RUNTIME_UID",gid="$RUNTIME_GID" \
  --tmpfs /var/log/bind:rw,mode=0755,size=16m,uid="$RUNTIME_UID",gid="$RUNTIME_GID" \
  "$IMAGE" >/dev/null

attempt=0
while [ "$attempt" -lt 45 ]; do
  status=$(docker inspect -f \
    '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
    "$CONTAINER")
  case "$status" in
    healthy)
      runtime_settings=$(docker exec "$CONTAINER" /bin/sh -c '
        pid=$(pidof named) || exit 1
        uid=$(awk "/^Uid:/{print \$2; exit}" /proc/"$pid"/status)
        gid=$(awk "/^Gid:/{print \$2; exit}" /proc/"$pid"/status)
        printf "%s:%s" "$uid" "$gid"
      ')
      if [ "$runtime_settings" != "${RUNTIME_UID}:${RUNTIME_GID}" ]; then
        echo "Expected process identity '${RUNTIME_UID}:${RUNTIME_GID}', got '${runtime_settings}'" >&2
        docker logs "$CONTAINER" >&2
        exit 1
      fi
      echo "Hardened container smoke test passed (bind9)"
      exit 0
      ;;
    exited|dead|unhealthy)
      docker logs "$CONTAINER" >&2
      echo "Container ended before becoming healthy (bind9): $status" >&2
      exit 1
      ;;
  esac
  attempt=$((attempt + 1))
  sleep 1
done

docker logs "$CONTAINER" >&2
echo "Container did not become healthy within 45 seconds (bind9)" >&2
exit 1
