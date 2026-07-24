# Site-specific BIND config (contents gitignored except this note).
#
#   cp ../examples/named.conf ./named.conf
#   # optional DDNS:
#   cp ../examples/ddns-tsig.key.example ./ddns-tsig.key
#   cp ../examples/named.conf.ddns.example ./named.conf.ddns
#   # then uncomment include "/etc/bind/named.conf.ddns"; in named.conf
#
# Mount this directory as BIND_CONFIG_DIR → /etc/bind.
# TLS PEMs go in certs/bind (BIND_CERT_DIR → /etc/bind/certs), not here.
#
# Never commit ddns-tsig.key, keys.conf, named.conf.keys, or private keys.
