# girihelix

Interactive generation and rendering of Islamic star patterns, written in
Elixir and rendered to SVG. A design tool in the browser for exploring
n-fold stars, rosettes, and the inferred patterns that fill the spaces
between them.

## Status

Early stages. The core algorithms are being ported from the reference
implementation; see [documentation](#documentation) for the analysis that
drives the port.

## Background

girihelix is a from-scratch reimplementation of the computational core of
**Taprats** — Craig S. Kaplan's Java design tool for computer-generated
Islamic patterns. Two versions of the original Java source are preserved under
[`reference/`](reference/). Both are git-ignored, so neither is published.
Neither is compiled or executed by this project; they exist so the port can be
checked against the original algorithms, line by line where necessary.

- **`reference/1.1.12/`** — Taprats 1.1.12, the current maintained release by
  Kaplan and Pierre Baillargeon, at changeset `b6c172`. This is the version to
  port from. It is GPL, so it could be redistributed, but it is deliberately kept
  out of the repository as well, keeping third-party source out of the published
  tree.
- **`reference/0.3/`** — the original 2000 release, kept as a second opinion on
  the older algorithms. Its licence reserves all rights and forbids
  redistribution outright.

Where the two disagree, 1.1.12 is authoritative except where a difference is
noted in the analysis document.

## What it generates

- `[n/d]s` **stars** — the classic n-fold star figures built from chord
  intersections inside one wedge, replicated by rotational symmetry.
- **Rosettes** — Kaplan's parameterized realization of Lee's rosette
  construction (star surrounded by petals), with a continuous `q`
  sharpness parameter.
- **Extended figures** — scaled and connected variants of stars and
  rosettes whose rays join with their rotated copies.
- **Inferred regions** — pattern line segments automatically invented for
  tiles that have no assigned figure, by extending rays from the figures
  in surrounding tiles (Kaplan's polygon-in-contact inference).
- **Interlace rendering** — an over/under weave assignment propagated
  across the pattern, the visual signature of girih strapwork.

All output is SVG, generated server-side and displayed via Phoenix
LiveView.

## Tech stack

- Elixir
- Phoenix + LiveView (interactive editors in the browser)
- Ash framework for domain modeling
- SVG for all rendering

## Documentation

- [Algorithm analysis of the Taprats reference implementation](docs/algorithm-analysis.md)

## Licence

girihelix is free software, licensed under the **GNU General Public License,
version 3 or later**. See [`LICENSE`](LICENSE).

It reimplements Taprats, which is itself GPL. Neither reference tree is part of
this repository — both are git-ignored and kept locally — so the published tree
contains no third-party source, and contributors obtain the upstream reference
themselves. The reasoning, including a licence discrepancy in the upstream
project, is recorded in [the analysis document](docs/algorithm-analysis.md).
