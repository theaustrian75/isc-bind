# ISC BIND 9 containers

Alpine 3.24 image for **bind9** (Do53 / optional DoT / DoH). Config, TSIG/DDNS keys, and TLS material are mounted at runtime. The process drops to configurable `BIND_UID`/`BIND_GID` via `setpriv` with ambient `NET_BIND_SERVICE` so it can bind port 53 after the drop — do **not** enable `no-new-privileges` or those caps are cleared and bind fails with `Permission denied`.

## Images

| Dockerfile | Packages | GHCR |
|---|---|---|
| `Dockerfile.bind9` | `bind`, `bind-tools`, plugins, dnssec tools | `ghcr.io/theaustrian75/isc-bind/bind9` |

Tags: `latest` (default branch), `main`, `sha-*`, and `v*` releases. Multi-arch (`amd64` / `arm64`).

Build args / runtime env:

| Variable | Default | Purpose |
|---|---|---|
| `BIND_UID` | `100` | Numeric UID after privilege drop (override via `.env` / `-e`; rebuild optional) |
| `BIND_GID` | `101` | Numeric GID after privilege drop (override via `.env` / `-e`; rebuild optional) |
| `TZ` | `UTC` | IANA timezone |
| `SKIP_CONFIG_TEST` | `false` | Skip `named-checkconf -z` before start |
| `BIND_CONFIG` | `/etc/bind/named.conf` | Main config path inside the container |
| `BIND_LOG_FILE` | _(empty)_ | If set, `named -L`; otherwise log to stderr (`-g`) |
| `BIND_HEALTHCHECK_SERVER` | `127.0.0.1` | `dig @` target |
| `BIND_HEALTHCHECK_PORT` | `53` | Do53 port |
| `BIND_HEALTHCHECK_QNAME` | `hostname.bind` | Healthcheck query name |
| `BIND_HEALTHCHECK_QTYPE` | `TXT` | Healthcheck type |
| `BIND_HEALTHCHECK_CLASS` | `CH` | Healthcheck class (CHAOS) |

Compose-only host paths: `BIND_CONFIG_DIR`, `BIND_CERT_DIR`, `BIND9_IMAGE`, `BIND9_CONTAINER_NAME`.

## Build & test

```bash
docker build --tag isc-bind/bind9:test --file Dockerfile.bind9 .

tests/test-container.sh isc-bind/bind9:test
tests/test-named-checkconf.sh isc-bind/bind9:test
```

CI mirrors [isc-kea](https://github.com/theaustrian75/isc-kea): validate → per-arch GHCR push → multi-arch merge.

## Compose / Quadlet

```bash
cp .env.example .env
# Set BIND_UID / BIND_GID to the host user that owns config and data volumes.
# named.conf (+ optional TSIG/DDNS includes) -> BIND_CONFIG_DIR  (/etc/bind)
# DoT/DoH/rndc PEM material                 -> BIND_CERT_DIR     (/etc/bind/certs)
docker compose up -d
```

`BIND_UID` / `BIND_GID` are applied at runtime by `setpriv` (and as compose build-args when you rebuild). Pulling a GHCR image is enough — set the env vars; you do not need a custom image per UID.

Quadlet unit: `bind9.container` (set `User=0` so the entrypoint can chown, then drops to `BIND_UID`/`BIND_GID`). Quadlet `Tmpfs=` may set `uid`/`gid` to match; Compose cannot (Docker rejects those options), so compose relies on entrypoint `chown`. Do **not** set `NoNewPrivileges` / `no-new-privileges` (ambient `NET_BIND_SERVICE`).

Example configs (including DDNS/TSIG): `config/examples/`.

## Dynamic DNS (TSIG)

Kea `dhcp-ddns` / `nsupdate` authenticate with a shared TSIG key — treat that secret like a password.

```bash
cp config/examples/ddns-tsig.key.example config/bind/ddns-tsig.key
cp config/examples/named.conf.ddns.example config/bind/named.conf.ddns
# replace secret: tsig-keygen -a hmac-sha256 dhcp-ddns
# uncomment: include "/etc/bind/named.conf.ddns";  in named.conf
```

Never commit `ddns-tsig.key`, `keys.conf`, or `named.conf.keys` (gitignored).

## Runtime volumes

| Path | Purpose |
|---|---|
| `/etc/bind` | `named.conf` + includes / TSIG (RO mount) |
| `/etc/bind/certs` | Optional TLS PEMs for DoT/DoH (nested RO mount) |
| `/var/cache/bind` | Working directory / cache |
| `/var/lib/bind` | Zone files / journals |
| `/var/log/bind` | File logs when `BIND_LOG_FILE` is set |
| `/run/named` | Runtime (tmpfs) |
