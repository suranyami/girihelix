defmodule Girihelix.Engine.Figures.ExplicitFigure do
  @moduledoc """
  A figure whose map is supplied rather than built.

  The stored map is the whole figure: `build_unit/1` returns it unchanged and
  `Figure.map/1` returns it without replication. Nothing is copied, turned or
  merged, so the caller keeps full control of the geometry.

  **This figure is not radial.** It has no symmetry order, implements no `n/1`
  and declares only `Figure`, so `Figure.radial?/1` answers `false`.
  """

  @behaviour Girihelix.Engine.Figures.Figure

  alias Girihelix.Engine.Figures.Figure
  alias Girihelix.Engine.PlanarMap

  @enforce_keys [:map]
  defstruct [:map]

  @type t :: %__MODULE__{map: PlanarMap.t()}
  @type reason :: :not_a_map

  @doc """
  Wraps `map`, which must be a `PlanarMap`.

  Anything else is refused with `{:error, :not_a_map}` rather than raising;
  `new!/1` raises.
  """
  @spec new(PlanarMap.t()) :: {:ok, t()} | {:error, reason()}
  def new(map) when is_struct(map, PlanarMap), do: {:ok, %__MODULE__{map: map}}
  def new(_map), do: {:error, :not_a_map}

  @doc "`new/1` for a caller that has the map, raising otherwise."
  @spec new!(term()) :: t()
  def new!(map) do
    case new(map) do
      {:ok, figure} -> figure
      {:error, reason} -> raise ArgumentError, "explicit figure: #{reason}"
    end
  end

  @impl Figure
  @spec build_unit(t()) :: PlanarMap.t()
  def build_unit(%__MODULE__{map: map}), do: map
end
