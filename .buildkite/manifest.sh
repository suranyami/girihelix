#!/usr/bin/env bash
# Assemble the multi-arch tags from the two per-platform images the parallel
# build steps pushed.
#
# Each build step pushed <image>:amd64-<sha> and <image>:arm64-<sha>. This step
# creates the tags the deploy and consumers use:
#   push to main -> sha-<short>, dev, main
#   tag v*       -> sha-<short>, <tag>, latest
#   otherwise    -> sha-<short>
#
# On a pull request PUSH is false, the build steps published nothing, and this
# step is a no-op.
set -euo pipefail

if [ "${PUSH:-false}" != "true" ]; then
  echo "PUSH=${PUSH:-false} — PR validation only, no manifest to publish"
  exit 0
fi

IMG="${IMAGE:-ghcr.io/suranyami/girihelix}"
SHA="${BUILDKITE_COMMIT:0:7}"
SOURCES=("$IMG:amd64-$SHA" "$IMG:arm64-$SHA")

: "${GHCR_TOKEN:?GHCR_TOKEN is not set — add it to the agent environment}"
echo "$GHCR_TOKEN" | docker login ghcr.io -u "${GHCR_USER:-suranyami}" --password-stdin

tags=("sha-$SHA")
if [ -n "${BUILDKITE_TAG:-}" ]; then
  tags+=("$BUILDKITE_TAG" "latest")
elif [ "${BUILDKITE_BRANCH:-}" = "main" ]; then
  tags+=("dev" "main")
fi

for tag in "${tags[@]}"; do
  echo "--- :package: $IMG:$tag"
  docker buildx imagetools create -t "$IMG:$tag" "${SOURCES[@]}"
done
