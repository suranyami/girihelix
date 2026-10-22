defmodule Girihelix.Engine.Tilings.Parser do
  @moduledoc """
  The `.tiling` text format, parsed into `Tiling` values.

  This is the faithful port of Taprats' tiling file reader (`Tiling.readTiling`,
  backed by a Java `StreamTokenizer`): the file is a flat token stream — the
  header, the two lattice generators, the features with their placement
  transforms, then the quoted description and author. Nothing is format-aware
  beyond the keyword and the quote character, so whitespace and line breaks
  carry no meaning; comments (`#`, `%`, `//` and `/* ... */`) and quoted
  strings are resolved while scanning.

  **Failures are data.** Where Taprats throws an `IOException` (or silently
  desynchronises), the port returns `{:error, reason}` tokens: a stream that
  does not start with the `tiling` keyword is `:not_a_tiling`, an unknown
  feature keyword is `{:bad_keyword, token}`, a short token stream is
  `:truncated`, and a token that is not a number is `:invalid_number` — the
  parser never skips a token it cannot read, so an error always means the file
  diverged, not that parsing continued desynchronised.

  **Description and author are sanitised.** Two shipped files carry non-UTF-8
  bytes (`Mughal.tiling` a cp1252 one, `pbn_7.tiling` a MacRoman one), so both
  strings are rebuilt as valid UTF-8, replacing each invalid byte with U+FFFD.
  Missing description or author at end of file are `nil`, as in Taprats.

  The sanitising happens before scanning: Elixir's `Regex` scans unicode text
  and rejects a subject with invalid sequences, while the format's tokens are
  ASCII outside quoted strings, so the text is repaired before the token scan
  touches it.
  """

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.Tilings.Feature
  alias Girihelix.Engine.Tilings.PlacedFeature
  alias Girihelix.Engine.Tilings.Tiling

  @type reason :: :not_a_tiling | {:bad_keyword, String.t()} | :truncated | :invalid_number

  @doc """
  Parses a `.tiling` text into a tiling.

  Feature ids come from `Feature.assign_ids/1` — one id per distinct tile, in
  order of first appearance — and each placement carries the id of the feature
  at its position.
  """
  @spec parse(String.t()) :: {:ok, Tiling.t()} | {:error, reason()}
  def parse(text), do: text |> sanitise() |> tokenize() |> parse_tiling()

  @doc """
  Parses a `.tiling` file into a tiling.

  A read failure passes the posix error through, so a missing file is
  distinguishable from a malformed one.
  """
  @spec parse_file(Path.t()) :: {:ok, Tiling.t()} | {:error, reason() | File.posix()}
  def parse_file(path) do
    case File.read(path) do
      {:ok, text} -> parse(text)
      {:error, reason} -> {:error, reason}
    end
  end

  # Scanning
  #
  # Taprats' StreamTokenizer: quoted strings are single tokens, the four
  # comment styles are honoured outside them, and everything else splits on
  # whitespace. One regex covers both, so a comment marker inside a quoted
  # string stays part of the string.

  @token_regex ~r{"([^"]*)"|//[^\n]*|#[^\n]*|%[^\n]*|/\*[\s\S]*?\*/|[^\s"]+}

  # The number forms of the format: optional sign, mantissa with an optional
  # dot (E notation included), as in the shipped files' `-1.1E-14`.
  @number_regex ~r{^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$}

  defp tokenize(text) do
    matches = Regex.scan(@token_regex, text)

    Enum.flat_map(matches, &token_from/1)
  end

  # A scan result is the full match plus only the capture groups that took
  # part: a quoted string yields two elements (its content may be empty), a
  # comment or a plain word yields one. Comment markers identify comments; a
  # quoted match always starts with the quote, which no other match does.
  defp token_from(["\"\"", quote]), do: [quote]
  defp token_from([_full, quote]), do: [quote]

  defp token_from(["#" <> _rest]), do: []
  defp token_from(["%" <> _rest]), do: []
  defp token_from(["//" <> _rest]), do: []
  defp token_from(["/*" <> _rest]), do: []
  defp token_from([word]), do: [word]

  # Parsing
  #
  # Each step consumes a token list and returns `{:ok, value, rest}` or an
  # `{:error, reason}`; a `with` threads them and passes any failure through
  # unchanged.

  defp parse_tiling(tokens) do
    with {:ok, tokens} <- tiling_keyword(tokens),
         {:ok, name, tokens} <- text_token(tokens),
         {:ok, feature_count, tokens} <- integer_token(tokens),
         {:ok, t1x, tokens} <- float_token(tokens),
         {:ok, t1y, tokens} <- float_token(tokens),
         {:ok, t2x, tokens} <- float_token(tokens),
         {:ok, t2y, tokens} <- float_token(tokens),
         {:ok, pairs, tokens} <- features(feature_count, tokens, []),
         {:ok, description, tokens} <- optional_text_token(tokens),
         {:ok, author, _rest} <- optional_text_token(tokens) do
      {features, placements} = materialise(pairs)

      {:ok,
       Tiling.new(
         name: name,
         description: sanitise(description),
         author: sanitise(author),
         t1: Point.new(t1x, t1y),
         t2: Point.new(t2x, t2y),
         features: features,
         placements: placements
       )}
    end
  end

  defp tiling_keyword(["tiling" | rest]), do: {:ok, rest}
  defp tiling_keyword([]), do: {:error, :not_a_tiling}
  defp tiling_keyword([_other | _rest]), do: {:error, :not_a_tiling}

  defp text_token([text | rest]), do: {:ok, text, rest}
  defp text_token([]), do: {:error, :truncated}

  defp optional_text_token([]), do: {:ok, nil, []}
  defp optional_text_token([text | rest]), do: {:ok, text, rest}

  defp integer_token([word | rest]), do: integer_parsed(Integer.parse(word), rest)
  defp integer_token([]), do: {:error, :truncated}

  defp integer_parsed({value, ""}, rest), do: {:ok, value, rest}
  defp integer_parsed(_other, _rest), do: {:error, :invalid_number}

  defp float_token([word | rest]), do: number_parsed(Regex.match?(@number_regex, word), word, rest)

  defp float_token([]), do: {:error, :truncated}

  defp number_parsed(true, word, rest), do: {:ok, to_float(word), rest}
  defp number_parsed(false, _word, _rest), do: {:error, :invalid_number}

  # `String.to_float/1` covers the decimal and E-notation forms the shipped
  # files use; a bare integer (`"4"`, which Java's Double accepts) falls back
  # to `String.to_integer/1`. The branch is on a matched boolean, so it splits
  # across heads.
  defp to_float(word), do: bare_integer(Regex.match?(~r{^[-+]?\d+$}, word), word)

  defp bare_integer(true, word), do: String.to_integer(word) * 1.0
  defp bare_integer(false, word), do: String.to_float(word)

  defp features(0, tokens, acc), do: {:ok, Enum.reverse(acc), tokens}

  defp features(count, tokens, acc) when count > 0 do
    with {:ok, feature, transforms, tokens} <- parse_feature(tokens) do
      features(count - 1, tokens, [{feature, transforms} | acc])
    end
  end

  defp features(_count, _tokens, _acc), do: {:error, :invalid_number}

  defp parse_feature(["regular" | rest]) do
    with {:ok, sides, rest} <- integer_token(rest),
         {:ok, count, rest} <- integer_token(rest),
         {:ok, transforms, rest} <- transforms(count, rest, []) do
      {:ok, Feature.new(regular: sides, points: []), transforms, rest}
    end
  end

  defp parse_feature(["polygon" | rest]) do
    with {:ok, point_count, rest} <- integer_token(rest),
         {:ok, count, rest} <- integer_token(rest),
         {:ok, points, rest} <- points(point_count, rest, []),
         {:ok, transforms, rest} <- transforms(count, rest, []) do
      {:ok, Feature.new(regular: nil, points: points), transforms, rest}
    end
  end

  defp parse_feature([other | _rest]), do: {:error, {:bad_keyword, other}}
  defp parse_feature([]), do: {:error, :truncated}

  defp points(0, tokens, acc), do: {:ok, Enum.reverse(acc), tokens}

  defp points(count, tokens, acc) when count > 0 do
    with {:ok, x, tokens} <- float_token(tokens),
         {:ok, y, tokens} <- float_token(tokens) do
      points(count - 1, tokens, [Point.new(x, y) | acc])
    end
  end

  defp points(_count, _tokens, _acc), do: {:error, :invalid_number}

  defp transforms(0, tokens, acc), do: {:ok, Enum.reverse(acc), tokens}

  defp transforms(count, tokens, acc) when count > 0 do
    with {:ok, a, tokens} <- float_token(tokens),
         {:ok, b, tokens} <- float_token(tokens),
         {:ok, c, tokens} <- float_token(tokens),
         {:ok, d, tokens} <- float_token(tokens),
         {:ok, e, tokens} <- float_token(tokens),
         {:ok, f, tokens} <- float_token(tokens) do
      transforms(count - 1, tokens, [Transform.new(a, b, c, d, e, f) | acc])
    end
  end

  defp transforms(_count, _tokens, _acc), do: {:error, :invalid_number}

  # Placement ids index the feature list, and `assign_ids/1` returns features
  # in input order, so zipping the assigned features with each feature's
  # transform group places every placement under the right id.
  defp materialise(pairs) do
    features = Enum.map(pairs, &elem(&1, 0))
    assigned = Feature.assign_ids(features)

    placements =
      pairs
      |> Enum.zip(assigned)
      |> Enum.flat_map(fn {{_feature, group}, feature} -> groups(feature, group) end)

    {assigned, placements}
  end

  defp groups(%Feature{id: id}, transforms), do: Enum.map(transforms, &PlacedFeature.new(id, &1))

  # Sanitising
  #
  # Decodes byte by byte: a valid UTF-8 codepoint passes through, an invalid
  # byte becomes U+FFFD, so `description` and `author` are always strings the
  # rest of the engine can hold.

  defp sanitise(nil), do: nil
  defp sanitise(raw), do: repair(raw, "")

  defp repair(<<>>, acc), do: acc

  defp repair(<<codepoint::utf8, rest::binary>>, acc), do: repair(rest, <<acc::binary, codepoint::utf8>>)

  defp repair(<<_invalid, rest::binary>>, acc), do: repair(rest, <<acc::binary, 0xFFFD::utf8>>)
end
