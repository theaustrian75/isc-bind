# Mount this directory at /etc/bind/certs (see docker-compose.yml BIND_CERT_DIR).
#
# Expected filenames depend on your named.conf tls { } blocks, for example:
#   cert-file "/etc/bind/certs/fullchain.pem";
#   key-file  "/etc/bind/certs/privkey.pem";
#
# Lab configs may use BIND's "tls ephemeral" and leave this directory empty.
# Never commit real private keys — /certs/ is gitignored.
