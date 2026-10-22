# The tiling catalogue

The 60 `.tiling` files shipped with **Taprats 1.1.12**, copied unchanged from
`reference/1.1.12/tilings/` (nothing under `reference/` is committed). They are
the input of `Girihelix.Engine.Tilings.Parser` and the data behind
`Girihelix.Engine.Tilings.Catalogue`.

## Provenance

- Source: Taprats 1.1.12, `reference/1.1.12/tilings/`.
- Licence: Taprats is GPLv3 (`reference/1.1.12/License.txt`), so these copies
  carry the same licence.
- `index.json` is generated data: one `{name, file}` entry per `.tiling` file,
  where `name` is the tiling name declared in the file's `tiling` header (the
  name Taprats' own `KnownTilings` registry uses) and `file` is the file name.

## Known quirks

Two files carry descriptions written in a legacy single-byte encoding that is
not valid UTF-8: `Mughal.tiling` (a cp1252 byte) and `pbn_7.tiling` (a MacRoman
byte). The parser sanitises both strings, replacing each invalid byte with
U+FFFD, so every loaded description is a valid UTF-8 string; name and geometry
are ASCII and unchanged.
