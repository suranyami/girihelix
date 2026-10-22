defmodule Girihelix.Engine.FigureFixtures.Square do
  @moduledoc """
  A test-only, four-fold figure whose unit is the single-side wedge from
  `(1.0, 0.0)` to `(0.0, 1.0)`.

  Four quarter turns produce the diamond's four sides, so a correct ladder
  leaves four vertices and four edges with no parallel duplicates. The unit
  itself is two vertices and one edge. It declares only `RadialFigure`, which
  carries both callbacks; declaring `Figure` as well would repeat `build_unit/1`
  and the compiler refuses that. `Figure` still dispatches to it, because a
  radial figure answers the same two functions.
  """

  @behaviour Girihelix.Engine.Figures.RadialFigure

  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap

  defstruct []

  @impl RadialFigure
  def build_unit(_figure) do
    map = PlanarMap.new()
    {map, from} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
    {map, to} = PlanarMap.insert_vertex(map, Point.new(0.0, 1.0))
    PlanarMap.insert_edge!(map, from, to)
  end

  @impl RadialFigure
  def n(_figure), do: 4
end

defmodule Girihelix.Engine.FigureFixtures.Counting do
  @moduledoc """
  A radial child that reports every unit build to the process in `:pid`.

  The cached-unit tests use it to prove a second build did not happen: a
  production path that rebuilds the child sends `:child_built` again.
  """

  @behaviour Girihelix.Engine.Figures.RadialFigure

  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Figures.Rosette

  defstruct [:pid]

  # RadialFigure's t/0 names the four production figures, so a test double is by
  # design outside that union. Suppress only the callback-argument warning: the
  # double's behaviour is exactly what the cached-unit tests exercise.
  @dialyzer {:nowarn_function, build_unit: 1}
  @impl RadialFigure
  def build_unit(%__MODULE__{pid: pid}) do
    send(pid, :child_built)
    Rosette.build_unit(Rosette.new!(8, 0.0, 3))
  end

  @impl RadialFigure
  def n(_figure), do: 8
end
