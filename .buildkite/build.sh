#!/usr/bin/env bash
# Build the girihelix container image for linux/amd64 and linux/arm64.
#
# Runs on the homelab Buildkite agent (itx, arm64) with the host docker socket
# mounted. arm64 builds natively; amd64 builds through QEMU binfmt, registered
# here so a fresh agent needs no host provisioning.
#
# Tags mirror what docker/metadata-action produced before the move:
#   push to main      -> sha-<short>, dev, main
#   tag v*            -> sha-<short>, <tag>, latest
#   anything else     -> sha-<short>
#
# PUSH=false builds both platforms into the cache without publishing, which is
# how pull requests validate the Dockerfile without pushing an image. PUSH must
# be set explicitly: a webhook-triggered build (no PUSH) never publishes, so a
# direct GitHub integration build cannot get ahead of the test gate.
set -euo pipefail

IMG="${IMAGE:-ghcr.io/suranyami/girihelix}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
BUILDER="${BUILDER:-girihelix-multi}"
SHA="${BUILDKITE_COMMIT:0:7}"

tags=("sha-$SHA")
if [ -n "${BUILDKITE_TAG:-}" ]; then
  tags+=("$BUILDKITE_TAG" "latest")
elif [ "${BUILDKITE_BRANCH:-}" = "main" ]; then
  tags+=("dev" "main")
fi

args=()
for t in "${tags[@]}"; do args+=(-t "$IMG:$t"); done

echo "--- :magic_wand: registering amd64 emulation"
docker run --privileged --rm tonistiigi/binfmt --install amd64

echo "--- :hammer: preparing the buildx builder"
if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  docker buildx create --name "$BUILDER" --driver docker-container
fi
docker buildx use "$BUILDER"
docker buildx inspect --bootstrap >/dev/null

echo "--- :docker: building $IMG for $PLATFORMS on $(uname -m)"
if [ "${PUSH:-false}" = "true" ]; then
  : "${GHCR_TOKEN:?GHCR_TOKEN is not set — add it to the agent environment}"
  echo "$GHCR_TOKEN" | docker login ghcr.io -u "${GHCR_USER:-suranyami}" --password-stdin
  docker buildx build --platform "$PLATFORMS" --push "${args[@]}" .
else
  docker buildx build --platform "$PLATFORMS" --output type=cacheonly "${args[@]}" .
  echo "PUSH=${PUSH:-false} — built both platforms, not pushed"
fi
