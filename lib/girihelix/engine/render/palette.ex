defmodule Girihelix.Engine.Render.Palette do
  @moduledoc """
  Sanzo Wada's colour combinations, indexed at compile time.

  `priv/palettes/colors.json` (vendored from `dblodorn/sanzo-wada`, see the
  README beside it) is decoded with the standard library's `JSON` at compile
  time into `@combinations`, a map from combination id to that combination's
  colours in dataset order. `@external_resource` makes the module recompile
  when the data changes. Nothing is read at runtime: the whole dataset is
  embedded in the beam.

  A combination is 1–5 named colours. `combination/1` returns them in dataset
  order; `roles/2` maps them to the slots a paint asks for.

  ## Role mapping

  Colours are sorted ascending by WCAG relative luminance — `hex` breaks ties —
  and `edge` takes the darkest. The rest are allocated by the roles requested:

  - `background` takes the lightest remaining colour, or, when no colour
    remains, a tone derived from the edge toward lighter;
  - `darker` and `lighter` take the most separated pair among the remaining
    colours, assigned by luminance order. One remaining colour becomes
    `lighter` and the other face is derived toward darker; no remaining colour
    derives both faces from the edge.

  A missing tone is derived in HSL: the hue and saturation are kept, lightness
  shifts by `0.18` and clamps to `[0.08, 0.92]`, and a shift that the clamp
  leaves unchanged reverses. The result is lowercase `#rrggbb`.

  The failure modes that remain are visual, not errors. A combination whose
  colours have near-identical luminance sorts arbitrarily and reads muddy, and
  a derived tone can be close to its base colour.
  """

  @external_resource "priv/palettes/colors.json"

  @colors JSON.decode!(File.read!("priv/palettes/colors.json"))["colors"]
  @count @colors |> Enum.flat_map(& &1["combinations"]) |> Enum.max()

  @combinations @colors
                |> Enum.flat_map(fn colour ->
                  Enum.map(colour["combinations"], fn id ->
                    {id,
                     %{
                       index: colour["index"],
                       name: colour["name"],
                       slug: colour["slug"],
                       hex: colour["hex"]
                     }}
                  end)
                end)
                |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

  # The ids are the bounded 1..348 range of the trusted local dataset, so the
  # atoms are a closed set created once at compile time.
  @options for id <- 1..@count, do: :"#{id}"

  @type colour :: %{
          index: pos_integer(),
          name: String.t(),
          slug: String.t(),
          hex: String.t()
        }

  @type roles :: %{atom() => String.t()}

  @known_roles [:edge, :background, :darker, :lighter]

  @role_step 0.18
  @role_min 0.08
  @role_max 0.92

  @doc """
  The number of combinations in the dataset.
  """
  @spec count() :: pos_integer()
  def count, do: @count

  @doc """
  Every combination id as an atom for the workbench enum: `:"1"` to `:"348"`.

  The atoms are the bounded 1–348 ids of the trusted local dataset: a closed
  set, compiled once.
  """
  @spec options() :: [atom()]
  def options, do: @options

  @doc """
  The colours of a combination, in dataset order.

  Accepts a combination id or its digit atom. Anything else — an unknown id,
  `:"0"`, a non-digit atom — is `{:error, :unknown_combination}`.
  """
  @spec combination(atom() | pos_integer()) ::
          {:ok, [colour()]} | {:error, :unknown_combination}
  def combination(id) do
    id |> fetch() |> combination_result()
  end

  defp combination_result(nil), do: {:error, :unknown_combination}
  defp combination_result(colours), do: {:ok, colours}

  @doc """
  The colours of a combination, raising `ArgumentError` when it is unknown.
  """
  @spec combination!(atom() | pos_integer()) :: [colour()]
  def combination!(id) do
    case combination(id) do
      {:ok, colours} -> colours
      {:error, :unknown_combination} -> raise ArgumentError, message: message(id)
    end
  end

  @doc """
  The paint roles a caller asks for, as hex strings.

  `roles` names the slots wanted, in any order, from `:edge`, `:background`,
  `:darker` and `:lighter`; the result carries exactly those keys. See the
  module doc for the luminance mapping and the derived tones.

  An unknown combination is `{:error, :unknown_combination}` and a role outside
  the four is `{:error, :unknown_role}`; the role list is validated first.
  """
  @spec roles(atom() | pos_integer(), [atom()]) ::
          {:ok, roles()} | {:error, :unknown_combination | :unknown_role}
  def roles(id, requested) do
    case validate_roles(requested) do
      :ok -> role_result(id, requested)
      {:error, _} = error -> error
    end
  end

  @doc """
  The paint roles a caller asks for, raising `ArgumentError` when the
  combination or a role is unknown.
  """
  @spec roles!(atom() | pos_integer(), [atom()]) :: roles()
  def roles!(id, requested) do
    case roles(id, requested) do
      {:ok, roles} ->
        roles

      {:error, :unknown_combination} ->
        raise ArgumentError, message: message(id)

      {:error, :unknown_role} ->
        raise ArgumentError, message: "unknown role in #{inspect(requested)}"
    end
  end

  # The combination's colours, or nil when the id names none.
  defp fetch(id) when is_integer(id), do: Map.get(@combinations, id)

  defp fetch(id) when is_atom(id) do
    id |> Atom.to_string() |> parse()
  end

  # Anything that is neither an integer nor an atom names no combination.
  defp fetch(_id), do: nil

  # The atom must be a whole number; a trailing remainder means it is not an id.
  defp parse(text) do
    case Integer.parse(text) do
      {id, ""} -> fetch(id)
      _remainder -> nil
    end
  end

  # Sorted ascending by luminance, hex breaking ties, then mapped by request.
  defp role_map(colours, requested) do
    [edge | remaining] = Enum.sort_by(colours, &{luminance(&1.hex), &1.hex})
    {background, rest} = background_value(remaining, edge, requested?(:background, requested))
    {darker, lighter} = face_values(rest, edge, requested)

    Map.take(
      %{edge: edge.hex, background: background, darker: darker, lighter: lighter},
      requested
    )
  end

  defp validate_roles(requested) do
    requested
    |> Enum.all?(&(&1 in @known_roles))
    |> roles_valid()
  end

  defp roles_valid(true), do: :ok
  defp roles_valid(false), do: {:error, :unknown_role}

  defp role_result(id, requested) do
    case combination(id) do
      {:ok, colours} -> {:ok, role_map(colours, requested)}
      {:error, _} = error -> error
    end
  end

  # The background is the lightest remaining colour, or a lighter tone of the
  # edge when nothing remains. Its colour leaves the rest only when asked for.
  defp background_value([], edge, wanted) do
    {requested_hex(derive(edge.hex, :lighter), wanted), []}
  end

  defp background_value(remaining, _edge, wanted) do
    {requested_hex(List.last(remaining).hex, wanted), without_lightest(remaining, wanted)}
  end

  defp without_lightest(remaining, true), do: Enum.drop(remaining, -1)
  defp without_lightest(remaining, false), do: remaining

  defp face_values(rest, edge, requested) do
    faces(rest, edge, {requested?(:darker, requested), requested?(:lighter, requested)})
  end

  defp faces([], edge, {darker?, lighter?}) do
    {requested_hex(derive(edge.hex, :darker), darker?), requested_hex(derive(edge.hex, :lighter), lighter?)}
  end

  defp faces([one], _edge, {darker?, lighter?}) do
    {requested_hex(derive(one.hex, :darker), darker?), requested_hex(one.hex, lighter?)}
  end

  defp faces(rest, _edge, {darker?, lighter?}) do
    {requested_hex(hd(rest).hex, darker?), requested_hex(List.last(rest).hex, lighter?)}
  end

  defp requested?(role, requested), do: role in requested

  defp requested_hex(_hex, false), do: nil
  defp requested_hex(hex, true), do: hex

  # A missing tone: the same hue and saturation at a shifted lightness.
  defp derive(hex, :darker), do: hex |> to_hsl() |> shift(:darker) |> from_hsl()
  defp derive(hex, :lighter), do: hex |> to_hsl() |> shift(:lighter) |> from_hsl()

  defp to_hsl("#" <> hex) do
    {r, g, b} = rgb(hex)
    max = Enum.max([r, g, b])
    min = Enum.min([r, g, b])
    delta = max - min
    lightness = (max + min) / 2

    {r |> hue(g, b, max, delta) |> normalise_hue(), saturation(lightness, delta), lightness}
  end

  defp shift({hue, saturation, lightness}, :lighter),
    do: {hue, saturation, shifted(lightness, lightness + @role_step, lightness - @role_step)}

  defp shift({hue, saturation, lightness}, :darker),
    do: {hue, saturation, shifted(lightness, lightness - @role_step, lightness + @role_step)}

  # A shift the clamp leaves unchanged reverses, so a tone always moves.
  defp shifted(lightness, forward, backward) do
    forward |> clamp_lightness() |> choose_shift(lightness, backward)
  end

  defp choose_shift(clamped, original, _backward) when clamped != original, do: clamped
  defp choose_shift(_clamped, _original, backward), do: clamp_lightness(backward)

  defp clamp_lightness(lightness) when lightness < @role_min, do: @role_min
  defp clamp_lightness(lightness) when lightness > @role_max, do: @role_max
  defp clamp_lightness(lightness), do: lightness

  # The sRGB channels as 0..1 fractions.
  defp rgb(hex) do
    [r, g, b] =
      for offset <- [0, 2, 4],
          do: hex |> binary_part(offset, 2) |> String.to_integer(16) |> Kernel./(255)

    {r, g, b}
  end

  defp normalise_hue(hue) when hue < 0.0, do: hue + 360.0
  defp normalise_hue(hue), do: hue

  defp saturation(_lightness, delta) when delta == 0.0, do: 0.0
  defp saturation(lightness, delta), do: delta / (1 - abs(2 * lightness - 1))

  defp from_hsl({hue, saturation, lightness}) do
    chroma = (1 - abs(2 * lightness - 1)) * saturation
    second = chroma * (1 - abs(:math.fmod(hue / 60, 2) - 1))
    match = lightness - chroma / 2

    {r, g, b} = rgb_prime(hue, chroma, second)

    "#" <> hex_channel(r + match) <> hex_channel(g + match) <> hex_channel(b + match)
  end

  defp rgb_prime(hue, chroma, second) when hue < 60.0, do: {chroma, second, 0.0}
  defp rgb_prime(hue, chroma, second) when hue < 120.0, do: {second, chroma, 0.0}
  defp rgb_prime(hue, chroma, second) when hue < 180.0, do: {0.0, chroma, second}
  defp rgb_prime(hue, chroma, second) when hue < 240.0, do: {0.0, second, chroma}
  defp rgb_prime(hue, chroma, second) when hue < 300.0, do: {second, 0.0, chroma}
  defp rgb_prime(_hue, chroma, second), do: {chroma, 0.0, second}

  defp hex_channel(value) do
    value
    |> Kernel.*(255)
    |> round()
    |> clamp_channel()
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(2, "0")
  end

  defp clamp_channel(value) when value < 0, do: 0
  defp clamp_channel(value) when value > 255, do: 255
  defp clamp_channel(value), do: value

  # Hue in degrees. Zero for a grey; the red maximum wraps modulo six.
  defp hue(_r, _g, _b, _max, delta) when delta == 0.0, do: 0.0
  defp hue(r, g, b, max, delta) when max == r, do: 60 * :math.fmod((g - b) / delta, 6)
  defp hue(r, g, b, max, delta) when max == g, do: 60 * ((b - r) / delta + 2)
  defp hue(r, g, b, max, delta) when max == b, do: 60 * ((r - g) / delta + 4)

  # WCAG relative luminance over the sRGB channels.
  defp luminance("#" <> hex) do
    [r, g, b] =
      for offset <- [0, 2, 4], do: hex |> binary_part(offset, 2) |> String.to_integer(16)

    0.2126 * linearise(r) + 0.7152 * linearise(g) + 0.0722 * linearise(b)
  end

  # Linearise one 0–255 channel, then weight it.
  defp linearise(channel), do: channel |> Kernel./(255) |> gamma()

  defp gamma(c) when c <= 0.03928, do: c / 12.92
  defp gamma(c), do: ((c + 0.055) / 1.055) ** 2.4

  defp message(id), do: "unknown combination: #{inspect(id)}"
end
