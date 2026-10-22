#!/usr/bin/env bash
# Build one platform of the girihelix container image.
#
# PLATFORM selects the target: linux/amd64 or linux/arm64. The pipeline runs
# two of these steps in parallel; a third step (manifest.sh) assembles the
# final multi-arch tags. Each platform gets its own log, cache and retry.
#
# PLATFORM=linux/amd64 builds through QEMU binfmt; arm64 is native.
# PUSH must be "true" to publish. Anything else builds into the cache only,
# which is how pull requests validate the Dockerfile.
set -euo pipefail

IMG="${IMAGE:-ghcr.io/suranyami/girihelix}"
PLATFORM="${PLATFORM:-linux/arm64}"
ARCH="${PLATFORM#linux/}"
BUILDER="${BUILDER:-girihelix-multi}"
SHA="${BUILDKITE_COMMIT:0:7}"
TAG="$IMG:$ARCH-$SHA"

if [ "$PLATFORM" = "linux/amd64" ]; then
  echo "--- :magic_wand: registering amd64 emulation"
  docker run --privileged --rm tonistiigi/binfmt --install amd64
fi

echo "--- :hammer: preparing the buildx builder"
if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  docker buildx create --name "$BUILDER" --driver docker-container >/dev/null 2>&1 || true
fi
docker buildx use "$BUILDER"
docker buildx inspect --bootstrap >/dev/null

echo "--- :docker: building $IMG for $PLATFORM on $(uname -m)"
if [ "${PUSH:-false}" = "true" ]; then
  : "${GHCR_TOKEN:?GHCR_TOKEN is not set — add it to the agent environment}"
  echo "$GHCR_TOKEN" | docker login ghcr.io -u "${GHCR_USER:-suranyami}" --password-stdin
  docker buildx build --platform "$PLATFORM" --push -t "$TAG" .
else
  docker buildx build --platform "$PLATFORM" --output type=cacheonly -t "$TAG" .
  echo "PUSH=${PUSH:-false} — built $PLATFORM, not pushed"
fi
