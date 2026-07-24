#!/bin/bash
set -euo pipefail

# Optional local overrides (REGISTRY, REPOSITORY, REGISTRY_USER, PODMAN_SECRET, TAG)
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

REGISTRY=${REGISTRY:-registry.klausk.xyz:8443}
REPOSITORY=${REPOSITORY:-repositories/dragonsnest}
REGISTRY_USER=${REGISTRY_USER:-dn-registry}
PODMAN_SECRET=${PODMAN_SECRET:-dn-registry-password}
TAG=${TAG:-latest}

echo "(1) Login as ${REGISTRY_USER}"
podman login -u "${REGISTRY_USER}" --secret "${PODMAN_SECRET}" "${REGISTRY}/${REPOSITORY}"

echo "(2) Delete old containers/volumes/images"
podman container prune -f
podman volume prune -f
podman image prune -af

for DOCKERFILE in "${PWD}"/Dockerfile.*; do
  IMAGE="${DOCKERFILE##*.}"
  echo "  (2.1) Delete old images and manifest"
  podman manifest rm "${REGISTRY}/${REPOSITORY}/${IMAGE}:${TAG}" || true

  echo "  (2.2) Building images"
  podman build \
    --format docker \
    --platform linux/amd64,linux/arm64 \
    --manifest "${REGISTRY}/${REPOSITORY}/${IMAGE}:${TAG}" \
    --tag "${IMAGE}:${TAG}-amd64" \
    --tag "${IMAGE}:${TAG}-arm64" \
    --file "${DOCKERFILE}" .

  echo "  (2.3) Pushing images to registry"
  podman manifest push --all "${REGISTRY}/${REPOSITORY}/${IMAGE}:${TAG}"
done

echo "(3) Logout"
podman logout "${REGISTRY}/${REPOSITORY}"
