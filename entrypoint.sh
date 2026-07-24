#!/bin/sh
# Entrypoint for the bind9 image.
# BIND_UID/BIND_GID are overridable at runtime; config is bind-mounted at /etc/bind.
set -eu

BIND_UID="${BIND_UID:-100}"
BIND_GID="${BIND_GID:-101}"
TZ="${TZ:-UTC}"
SKIP_CONFIG_TEST="${SKIP_CONFIG_TEST:-false}"
BIND_CONFIG="${BIND_CONFIG:-/etc/bind/named.conf}"
# Empty = log to stderr (container-friendly). Set to a path under /var/log/bind for file logs.
BIND_LOG_FILE="${BIND_LOG_FILE:-}"

BIN=/usr/sbin/named

validate_id() {
  variable=$1
  value=$2
  case "$value" in
    *[!0-9]*|"")
      echo "$variable must be a non-zero numeric ID" >&2
      exit 1
      ;;
  esac
  if [ "$value" -eq 0 ]; then
    echo "$variable must be a non-zero numeric ID" >&2
    exit 1
  fi
}

validate_id BIND_UID "$BIND_UID"
validate_id BIND_GID "$BIND_GID"

case "$TZ" in
  /*|*..*|*[!a-zA-Z0-9_+./-]*|"")
    echo "TZ must be an installed IANA timezone (for example America/New_York)" >&2
    exit 1
    ;;
esac
if [ ! -f "/usr/share/zoneinfo/$TZ" ]; then
  echo "TZ is not installed: $TZ" >&2
  exit 1
fi
export TZ

case "$SKIP_CONFIG_TEST" in
  true|false) ;;
  *)
    echo "SKIP_CONFIG_TEST must be true or false" >&2
    exit 1
    ;;
esac

if [ ! -f "$BIND_CONFIG" ]; then
  echo "Required configuration file is missing: $BIND_CONFIG (mount /etc/bind)" >&2
  exit 1
fi
if [ ! -r "$BIND_CONFIG" ]; then
  echo "Required configuration file is not readable by uid $(id -u): $BIND_CONFIG" >&2
  exit 1
fi

# Optional TLS material: require every /etc/bind/certs/... path referenced in config.
tls_paths=$(grep -Eo '/etc/bind/certs/[^"[:space:];]+' "$BIND_CONFIG" 2>/dev/null | sort -u || true)
# Also scan common includes if present.
for inc in /etc/bind/named.conf.local /etc/bind/named.conf.ddns; do
  if [ -f "$inc" ] && [ -r "$inc" ]; then
    tls_paths=$(printf '%s\n%s\n' "$tls_paths" \
      "$(grep -Eo '/etc/bind/certs/[^"[:space:];]+' "$inc" 2>/dev/null || true)" | sort -u)
  fi
done
if [ -n "$tls_paths" ]; then
  while IFS= read -r tls_file; do
    [ -n "$tls_file" ] || continue
    if [ ! -f "$tls_file" ]; then
      echo "Required TLS file is missing: $tls_file (referenced in config)" >&2
      exit 1
    fi
    if [ ! -r "$tls_file" ]; then
      echo "Required TLS file is not readable by uid $(id -u): $tls_file" >&2
      exit 1
    fi
  done <<EOF
$tls_paths
EOF
fi

mkdir -p /run/named /var/cache/bind /var/lib/bind /var/log/bind
# Quadlet/podman can set tmpfs uid=/gid= at mount time; Compose/Docker cannot.
# Chown here (needs CAP_CHOWN) so the dropped-privilege process can write.
chmod 0750 /run/named 2>/dev/null || true
chown "${BIND_UID}:${BIND_GID}" /run/named /var/cache/bind /var/lib/bind /var/log/bind 2>/dev/null || true

if [ "$SKIP_CONFIG_TEST" = false ]; then
  if ! setpriv --reuid="$BIND_UID" --regid="$BIND_GID" --clear-groups -- \
    /usr/bin/named-checkconf -z "$BIND_CONFIG"; then
    echo "Configuration check failed for $BIND_CONFIG" >&2
    exit 1
  fi
fi

# Already dropped via setpriv — do not pass named -u (that path expects start-as-root).
# Ambient NET_BIND_SERVICE must survive setuid+exec to bind :53; omit no-new-privileges.
if [ -n "$BIND_LOG_FILE" ]; then
  set -- "$BIN" -f -c "$BIND_CONFIG" -L "$BIND_LOG_FILE"
else
  # -g: foreground + all logging to stderr (compose/journal friendly)
  set -- "$BIN" -g -c "$BIND_CONFIG"
fi

exec setpriv --reuid="$BIND_UID" --regid="$BIND_GID" --clear-groups \
  --inh-caps=-all,+net_bind_service \
  --ambient-caps=-all,+net_bind_service \
  -- "$@"
