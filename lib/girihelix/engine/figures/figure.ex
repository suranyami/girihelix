defmodule Girihelix.Engine.Figures.Figure do
  @moduledoc """
  A figure: something that builds a planar map, with or without rotational
  symmetry.

  `unit/1` is the figure's basic unit, before replication. `map/1` is the whole
  figure. `radial?/1` answers whether replication applies, without the caller
  matching on a struct.

  **`n/1` belongs to `RadialFigure`, not here.** A non-radial figure, such as an
  explicit map, has no symmetry order to invent, and `Figure` must be able to
  hold it without one.

  A radial figure is its unit replicated under its symmetry ladder; a non-radial
  one, such as `ExplicitFigure`, stores its whole map and `map/1` returns it
  unchanged. `map/1` therefore has one clause per kind.
  """

  alias Girihelix.Engine.Figures.ExplicitFigure
  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Figures.Rosette
  alias Girihelix.Engine.Figures.ScaleFigure
  alias Girihelix.Engine.Figures.Star
  alias Girihelix.Engine.PlanarMap

  # Only the figures defined today may appear here: a typespec naming an
  # undefined struct warns, and warnings are errors in this project. Task 6 adds
  # `ConnectFigure` to this union when its struct exists.
  @type t :: %Star{} | %Rosette{} | %ScaleFigure{} | %ExplicitFigure{}

  @doc "The figure's basic unit, before the `n`-fold replication."
  @callback build_unit(t()) :: PlanarMap.t()

  @doc "The figure's basic unit, before the `n`-fold replication."
  @spec unit(t()) :: PlanarMap.t()
  def unit(%module{} = figure), do: module.build_unit(figure)

  @doc """
  The whole figure.

  A radial figure is its unit replicated under its symmetry ladder; an explicit
  figure is its stored map.
  """
  @spec map(t()) :: PlanarMap.t()
  def map(%ExplicitFigure{map: map}), do: map
  def map(%_{} = figure), do: RadialFigure.map(figure)

  @doc """
  Whether `figure` is radial: one whose module implements `RadialFigure`.

  Read from the module's declared behaviours rather than a list of structs, so
  it needs no edit when a figure is added.
  """
  @spec radial?(t()) :: boolean()
  def radial?(%module{}), do: RadialFigure in behaviours(module)

  defp behaviours(module) do
    :attributes
    |> module.__info__()
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end
end
