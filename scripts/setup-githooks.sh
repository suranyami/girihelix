#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

chmod +x .githooks/pre-push
git config core.hooksPath .githooks

echo "Git hooks enabled: core.hooksPath=.githooks (pre-push runs mix precommit)"
