# AGENTS.md

## Cursor Cloud specific instructions

This repo builds a Docker image for **ISC BIND 9** (a DNS server). There is no
application runtime beyond Docker itself — the entire dev/test/run workflow is
Docker + `shellcheck`. Standard commands live in `README.md` ("Build & test")
and `.github/workflows/ci.yml` (the `validate` job mirrors CI exactly). Prefer
those sources; the notes below only cover non-obvious cloud-VM caveats.

### Docker daemon must be started manually
The Docker daemon is **not** managed by systemd in this VM. Start it once per
session (e.g. in a background/tmux shell):

```
sudo dockerd 2>&1 | tee /tmp/dockerd.log
```

After each `dockerd` start, make the socket usable by the `ubuntu` user (a fresh
daemon recreates the socket root-owned):

```
sudo chmod 666 /var/run/docker.sock
```

The daemon uses the `fuse-overlayfs` storage driver (`/etc/docker/daemon.json`)
and `iptables-legacy` — required for docker-in-docker in this environment.

### Known limitation: no `memory` cgroup controller
The VM's cgroup v2 root is a **threaded domain**, so the `memory` (and `io`/
`hugetlb`) controllers cannot be delegated to containers. Any `docker run
--memory ...` fails with:

```
cannot enter cgroupv2 "/sys/fs/cgroup/docker" with domain controllers -- it is in threaded mode
```

Consequences:
- `tests/test-named-checkconf.sh` passes (no resource limits).
- `tests/test-container.sh` fails **only** at its hardened `docker run
  --memory 256m` step; everything before it (image checks, no-secrets scan,
  failure-mode assertions) works, and `--pids-limit` works. This is an
  environment limitation, not a repo/image bug — it passes on GitHub CI.
  To smoke-test the hardened runtime here, run that container command minus
  `--memory` (it becomes `healthy` and `named` drops to the configured UID/GID).

### Running the server with docker compose
`docker compose up` reads `.env` and bind-mounts config. Non-obvious setup:
- Provide `config/bind/named.conf` (gitignored) — e.g. copy `config/examples/named.conf`.
- The nested read-only cert mount needs a mountpoint inside the RO config tree:
  `mkdir -p config/bind/certs` (otherwise startup fails with
  `read-only file system` when creating `/etc/bind/certs`).
- The compose default image is the GHCR one; set `BIND9_IMAGE=isc-bind/bind9:test`
  in `.env` to use a locally built image.
- Query the running server with `docker compose exec bind9 dig ...`.
