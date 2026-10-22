#!/usr/bin/env bash
# Build the girihelix container image natively for linux/arm64.
#
# Runs on the homelab Buildkite agent (itx, arm64) with the host docker socket
# mounted, so there is no buildx and no QEMU: the build is native and produces
# an arm64 image because the host is arm64.
#
# Tags mirror what docker/metadata-action produced before the move:
#   push to main      -> sha-<short>, dev, main
#   tag v*            -> sha-<short>, <tag>, latest
#   anything else     -> sha-<short>
#
# PUSH=false builds without publishing, which is how pull requests validate the
# Dockerfile without pushing an image.
set -euo pipefail

IMG="${IMAGE:-ghcr.io/suranyami/girihelix}"
SHA="${BUILDKITE_COMMIT:0:7}"

tags=("sha-$SHA")
if [ -n "${BUILDKITE_TAG:-}" ]; then
  tags+=("$BUILDKITE_TAG" "latest")
elif [ "${BUILDKITE_BRANCH:-}" = "main" ]; then
  tags+=("dev" "main")
fi

args=()
for t in "${tags[@]}"; do args+=(-t "$IMG:$t"); done

echo "--- :docker: building $IMG on $(uname -m)"
docker build "${args[@]}" .

if [ "${PUSH:-true}" = "true" ]; then
  : "${GHCR_TOKEN:?GHCR_TOKEN is not set — add it to the agent environment}"
  echo "--- :key: pushing ${tags[*]}"
  echo "$GHCR_TOKEN" | docker login ghcr.io -u "${GHCR_USER:-suranyami}" --password-stdin
  for t in "${tags[@]}"; do docker push "$IMG:$t"; done
else
  echo "PUSH=$PUSH — built only, not pushed"
fi
