#!/usr/bin/env bash
#
# Repair the Tailwind standalone CLI's code signature.
#
# The binary the `tailwind` hex package downloads currently ships with an INVALID
# signature -- verified with `codesign --verify --strict`, which reports
# "invalid signature (code or signature have been modified)". macOS SIGKILLs any
# binary whose signature fails to validate, so `mix assets.build` dies with
#
#     ** (Mix) `mix tailwind girihelix` exited with 137
#
# and no priv/static/assets/css/ is produced. The failure is silent and confusing:
# the binary dies before printing anything, even for `--help`, so it looks like a
# missing input file or a bad Tailwind config rather than a signing problem.
#
# Re-downloading does NOT help -- the published artifact is consistently broken.
# Re-signing ad-hoc rewrites only the signature, not the executable code, and
# makes the binary runnable. The binaries live in _build/, so this must be re-run
# after any `mix clean` or fresh clone.
#
# Verified fix: after re-signing, the CLI prints "tailwindcss v4.3.0" and the build
# completes in ~70ms.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

fixed=0

for bin in "$root"/_build/tailwind-*; do
  # Nothing downloaded yet -- run `mix assets.setup` first.
  [ -f "$bin" ] || continue

  if codesign --verify --strict "$bin" 2>/dev/null; then
    continue
  fi

  echo "re-signing $(basename "$bin") (invalid signature)"
  codesign --force --sign - "$bin"
  fixed=1
done

if [ "$fixed" -eq 0 ]; then
  echo "all tailwind binaries already have valid code signatures"
fi
