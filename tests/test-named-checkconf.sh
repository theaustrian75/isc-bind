#!/bin/sh
# Validate tracked example configs with named-checkconf inside the image.
# Usage: tests/test-named-checkconf.sh IMAGE
set -eu

IMAGE="${1:?Usage: tests/test-named-checkconf.sh IMAGE}"
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)

# Invoked through trap.
# shellcheck disable=SC2317
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

mkdir -p "$TMP/etc" "$TMP/lib" "$TMP/cache"
cp "$ROOT/config/examples/named.conf" "$TMP/etc/named.conf"

# DDNS fragment needs a key + stub zone files for -z.
cp "$ROOT/config/examples/named.conf.ddns.example" "$TMP/etc/named.conf.ddns"
cat >"$TMP/etc/ddns-tsig.key" <<'EOF'
key "dhcp-ddns" {
	algorithm hmac-sha256;
	secret "dGVzdC1zZWNyZXQtdGVzdC1zZWNyZXQtdGVzdCE=";
};
EOF

cat >"$TMP/lib/db.example.com" <<'EOF'
$TTL 300
@	IN SOA	ns.example.com. hostmaster.example.com. (
		1 3600 600 86400 300 )
@	IN NS	ns.example.com.
ns	IN A	127.0.0.1
EOF

cat >"$TMP/lib/db.192.168.1" <<'EOF'
$TTL 300
@	IN SOA	ns.example.com. hostmaster.example.com. (
		1 3600 600 86400 300 )
@	IN NS	ns.example.com.
EOF

# Enable the DDNS include for this check only.
printf '\ninclude "/etc/bind/named.conf.ddns";\n' >>"$TMP/etc/named.conf"

echo "==> named-checkconf -z on example configs"
docker run --rm \
  -v "$TMP/etc:/etc/bind:ro" \
  -v "$TMP/lib:/var/lib/bind" \
  -v "$TMP/cache:/var/cache/bind" \
  --entrypoint /usr/sbin/named-checkconf \
  "$IMAGE" -z /etc/bind/named.conf

echo "Example named-checkconf passed"
