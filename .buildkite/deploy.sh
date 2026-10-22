#!/usr/bin/env bash
# Deploy the freshly pushed :dev image to the homelab's Uncloud cluster.
#
# Runs on the Buildkite agent container, which has only the host Docker socket.
# The deployment therefore runs in a sibling container with the host's static
# `uc` binary, the homelab checkout and the Uncloud API socket bind-mounted.
#
# Requires GIRIHELIX_SECRET_KEY_BASE in the Buildkite pipeline environment
# (masked); the service file interpolates it.
set -euo pipefail

: "${GIRIHELIX_SECRET_KEY_BASE:?add GIRIHELIX_SECRET_KEY_BASE to the Buildkite pipeline environment (masked)}"

docker run --rm \
  --platform linux/arm64 \
  -v /opt/homelab:/opt/homelab:ro \
  -v /run/uncloud:/run/uncloud \
  -v /usr/local/bin/uc:/usr/local/bin/uc:ro \
  -e UNCLOUD_CONNECT=unix:///run/uncloud/api/uncloud.sock \
  -e GIRIHELIX_SECRET_KEY_BASE \
  -e HOME=/tmp \
  -w /opt/homelab \
  --entrypoint /bin/sh \
  debian:bookworm-slim -c '
    set -eu
    printf "services:\n  girihelix:\n    pull_policy: always\n" > /tmp/pull-policy.yml
    /usr/local/bin/uc deploy -y -f services/girihelix/girihelix.yml -f /tmp/pull-policy.yml girihelix
  '
