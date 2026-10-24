defmodule GirihelixWeb.Workbench.Param do
  @moduledoc """
  One declarative parameter of a workbench exhibit, and the URL codec for it.

  An exhibit declares its parameters once, as a list of `Param` structs. The same
  declaration drives the controls, the URL and validation, so there is no second
  source of truth and no per-exhibit special case. This module is the URL half:
  it turns the string-keyed map LiveView receives from `handle_params/3` into a
  map of typed values, and back again.

  **The URL is untrusted.** A parameter may be absent, unparseable, out of range,
  repeated (Phoenix gives a list) or named by something that is not a parameter at
  all. None of those raise: an unknown key is ignored, and a missing or invalid
  value falls back to the parameter's default. A numeric value that parses clamps
  to `range.first..range.last`. Numeric parsing is strict — `"12px"` is not an
  integer — so a partly numeric string is invalid rather than silently truncated.

  **`:range` is integer-backed.** Elixir 1.20 ranges hold integers only, so a
  `:float` parameter declares its bounds as integers (`1..10`) and carries its
  precision in `:step` (`0.1`). Clamping and `values/2` coerce a float
  parameter's result back to a float, so `values/2` yields `1.0` and `10.0`, not
  `1` and `10`.

  **Enums never create atoms.** A string is matched against the declared options
  with `Atom.to_string/1`, never with `String.to_atom/1`, because the URL is user
  input and the atom table is finite.

  **`:palette` is an enum on the wire.** It decodes, encodes and takes its
  extremes exactly as an `:enum` does; only the control differs, rendering the
  combinations as colour swatches rather than a select.

  **Extremes are declarative too.** `values/2` yields every parameter at its
  default or at one end of its declared domain, which is what a property test and
  the index page's sample URLs need.
  """

  @enforce_keys [:name, :type]
  defstruct [:name, :type, :default, :doc, :range, :step, :options]

  @type type :: :integer | :float | :boolean | :enum | :palette
  @type value :: integer() | float() | boolean() | atom()
  @type t :: %__MODULE__{
          name: atom(),
          type: type(),
          default: value(),
          doc: String.t() | nil,
          range: Range.t() | nil,
          step: number() | nil,
          options: [atom()] | nil
        }

  @doc """
  Decodes a string-keyed URL map against `params`.

  Returns one atom-keyed entry per parameter, in the parameter's declared type.
  Keys in `input` that do not name a parameter are ignored. A parameter whose
  value is absent, not a string, or not valid for its type takes its default. A
  parsed `:integer` or `:float` is clamped to its `:range` when it has one.
  """
  @spec decode([t()], map()) :: %{atom() => value()}
  def decode(params, input) when is_list(params) and is_map(input) do
    Map.new(params, fn param ->
      {param.name, decode_value(param, Map.get(input, Atom.to_string(param.name)))}
    end)
  end

  @doc """
  Encodes `values` as the string-keyed map a query string can carry.

  Every declared parameter is emitted, whether or not it appears in `values`; a
  missing value takes the parameter's default. The result round-trips through
  `decode/2`.
  """
  @spec encode([t()], %{atom() => value()}) :: %{String.t() => String.t()}
  def encode(params, values) when is_list(params) and is_map(values) do
    Map.new(params, fn param ->
      {Atom.to_string(param.name), encode_value(param, Map.get(values, param.name, param.default))}
    end)
  end

  @doc """
  Every parameter at its default (`:default`) or at one of its extremes.

  `:first` and `:last` use the declared domain: a numeric parameter's range ends,
  an enum's first or last option, and a boolean's `false` or `true`. A parameter
  with no declared domain of that kind falls back to its default.
  """
  @spec values([t()], :default | :first | :last) :: %{atom() => value()}
  def values(params, :default), do: Map.new(params, &{&1.name, &1.default})
  def values(params, :first), do: Map.new(params, &{&1.name, extreme(&1, :first)})
  def values(params, :last), do: Map.new(params, &{&1.name, extreme(&1, :last)})

  defp decode_value(param, raw) do
    case parse(param, raw) do
      {:ok, value} -> clamp(param, value)
      :error -> param.default
    end
  end

  defp parse(%__MODULE__{type: :integer}, raw), do: parse_integer(raw)
  defp parse(%__MODULE__{type: :float}, raw), do: parse_float(raw)
  defp parse(%__MODULE__{type: :boolean}, raw), do: parse_boolean(raw)

  defp parse(%__MODULE__{type: type, options: options}, raw) when type in [:enum, :palette], do: parse_enum(raw, options)

  # Requiring an empty remainder is what makes "12px" invalid rather than 12.
  defp parse_integer(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {integer, ""} -> {:ok, integer}
      _partial -> :error
    end
  end

  defp parse_integer(_raw), do: :error

  defp parse_float(raw) when is_binary(raw) do
    case Float.parse(raw) do
      {float, ""} -> {:ok, float}
      _partial -> :error
    end
  end

  defp parse_float(_raw), do: :error

  defp parse_boolean("true"), do: {:ok, true}
  defp parse_boolean("false"), do: {:ok, false}
  defp parse_boolean(_raw), do: :error

  defp parse_enum(raw, options) when is_binary(raw) and is_list(options) do
    case Enum.find(options, fn option -> Atom.to_string(option) == raw end) do
      nil -> :error
      option -> {:ok, option}
    end
  end

  defp parse_enum(_raw, _options), do: :error

  defp clamp(%__MODULE__{range: range, type: type}, value) do
    value |> clamp_range(range) |> coerce(type)
  end

  defp clamp_range(value, %Range{first: first, last: last}) when is_number(value) do
    value |> max(first) |> min(last)
  end

  defp clamp_range(value, _range), do: value

  # An Elixir 1.20 range holds integers only, so a float parameter's range is
  # written with integer bounds and `step` carries the precision. Clamping can
  # land on an integer bound, so put the value back in the parameter's type.
  defp coerce(value, :float) when is_number(value), do: value * 1.0
  defp coerce(value, _type), do: value

  defp encode_value(%__MODULE__{type: :integer}, value) when is_integer(value) do
    Integer.to_string(value)
  end

  defp encode_value(%__MODULE__{type: :float}, value) when is_number(value) do
    to_string(value * 1.0)
  end

  defp encode_value(%__MODULE__{type: :boolean}, value) when is_boolean(value) do
    Atom.to_string(value)
  end

  defp encode_value(%__MODULE__{type: type}, value) when type in [:enum, :palette] and is_atom(value) do
    Atom.to_string(value)
  end

  defp extreme(%__MODULE__{type: :boolean}, :first), do: false
  defp extreme(%__MODULE__{type: :boolean}, :last), do: true

  defp extreme(%__MODULE__{type: type, options: [first | _]}, :first) when type in [:enum, :palette], do: first

  defp extreme(%__MODULE__{type: type, options: [_ | _] = options}, :last) when type in [:enum, :palette],
    do: List.last(options)

  defp extreme(%__MODULE__{type: :float, range: %Range{first: first}}, :first), do: first * 1.0
  defp extreme(%__MODULE__{type: :float, range: %Range{last: last}}, :last), do: last * 1.0
  defp extreme(%__MODULE__{range: %Range{first: first}}, :first), do: first
  defp extreme(%__MODULE__{range: %Range{last: last}}, :last), do: last
  defp extreme(%__MODULE__{default: default}, _which), do: default
end
