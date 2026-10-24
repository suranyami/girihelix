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
  order; `roles/1` maps them to the four slots a paint needs.

  ## Role mapping

  Colours are sorted ascending by WCAG relative luminance — `hex` breaks ties —
  and the sorted list is mapped by its length:

  - one colour: every role is that colour;
  - two `[dark, light]`: `edge` is dark; `darker`, `lighter` and `background`
    are light;
  - three `[dark, mid, light]`: `edge` dark, `darker` mid, `lighter` and
    `background` light;
  - four `[edge, dark, light, background]`: the four in order;
  - five or more: `edge` first, `darker` second, `lighter` second-to-last,
    `background` last.

  The failure modes are known and accepted for v1. A combination whose colours
  have near-identical luminance sorts arbitrarily and reads muddy, and a
  one-colour combination paints flat — every face and boundary the same. Both
  are visual, not errors.
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

  @type roles :: %{
          edge: String.t(),
          darker: String.t(),
          lighter: String.t(),
          background: String.t()
        }

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
  The four paint roles for a combination: `edge`, `darker`, `lighter` and
  `background`, as hex strings.

  See the module doc for the luminance rule. An unknown combination is
  `{:error, :unknown_combination}`.
  """
  @spec roles(atom() | pos_integer()) :: {:ok, roles()} | {:error, :unknown_combination}
  def roles(id) do
    case combination(id) do
      {:ok, colours} -> {:ok, role_map(colours)}
      {:error, _} = error -> error
    end
  end

  @doc """
  The four paint roles for a combination, raising `ArgumentError` when it is
  unknown.
  """
  @spec roles!(atom() | pos_integer()) :: roles()
  def roles!(id) do
    case roles(id) do
      {:ok, roles} -> roles
      {:error, :unknown_combination} -> raise ArgumentError, message: message(id)
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

  # Sorted ascending by luminance, hex breaking ties, then mapped by length.
  defp role_map(colours) do
    colours
    |> Enum.sort_by(&{luminance(&1.hex), &1.hex})
    |> assign_roles()
  end

  defp assign_roles([same]) do
    %{edge: same.hex, darker: same.hex, lighter: same.hex, background: same.hex}
  end

  defp assign_roles([dark, light]) do
    %{edge: dark.hex, darker: light.hex, lighter: light.hex, background: light.hex}
  end

  defp assign_roles([dark, mid, light]) do
    %{edge: dark.hex, darker: mid.hex, lighter: light.hex, background: light.hex}
  end

  defp assign_roles([edge, darker, lighter, background]) do
    %{edge: edge.hex, darker: darker.hex, lighter: lighter.hex, background: background.hex}
  end

  defp assign_roles([edge, darker | rest]) do
    %{
      edge: edge.hex,
      darker: darker.hex,
      lighter: Enum.at(rest, -2).hex,
      background: List.last(rest).hex
    }
  end

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
