defmodule GirihelixWeb.Workbench.Exhibits.Styles do
  @moduledoc """
  One catalogue tiling instanced with a figure, then painted by a render style.

  The exhibit runs `Construct`'s step sequence exactly as `Instancing` does. The
  chosen style paints the welded map in `draw/2`, never in a step: the frame
  carries the construction and nothing style- or palette-dependent, so a style,
  palette or `tiles` change redraws the same frame instead of reconstructing
  it. Frame zero and the construct's intermediate frames draw the same static
  structure `Instancing` shows, so a reader can step through the construction
  before the finished picture.

  With `tiles` on, the faint lattice overlay is composited above the figure, so
  the tile boundaries stay legible over the paint rather than hidden beneath it.

  **A finite patch behind a pinned window.** The construction fills a square
  patch of `2 * cells + 1` cells in each lattice direction, where `cells` comes
  from the run (two by default, one for a tiling the run measured as heavy), so
  every vertex the pinned window shows has its periodic counterparts a cell
  away. The window itself shows the same `cells` count, centred on the
  constructed map's own content, and the SVG root no longer clips, the wrapper
  does, so panning reveals the fringe rather than empty space.

  A map the style cannot paint still draws. An unbound run leaves the map empty,
  so `Filled` reports `:no_faces` and the panel falls back to the construct
  drawing; the same fallback covers an empty painting, such as `Plain` over an
  empty map. A raising star construction — tiling `3-8-12` — retains the frames
  it built before the exception, and every one of them draws.

  The panel reports the request beside the result: the tiling, figure, style and
  palette, then the filled face count (`n/a` for a style that fills none), the
  welded map's `vertices` and `edges`, and the failure reason or `none`.

  This is workbench code, not engine code: the construction is the `Construct`
  engine's step sequence and the painting is `Style.paint/3`, never a rebuild.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Bounds
  alias Girihelix.Engine.Render.Palette
  alias Girihelix.Engine.Render.Style
  alias Girihelix.Engine.Render.Viewport
  alias Girihelix.Engine.Steps
  alias Girihelix.Engine.Tilings.Catalogue
  alias Girihelix.Engine.Tilings.Construct
  alias Girihelix.Engine.Tilings.Tiling
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Exhibits.Figures
  alias GirihelixWeb.Workbench.Exhibits.Instancing
  alias GirihelixWeb.Workbench.Exhibits.Tilings
  alias GirihelixWeb.Workbench.Param

  # The patch is a finite square of cells around the origin; the pinned window
  # shows the same number. A 4:3 (aspect 0.75) canvas 1000 SVG units wide keeps
  # presentation sizes at their authored meaning. `:cells` is supplied by the
  # run's adaptive probe; two is the shipped default.
  @patch_cells 2
  @canvas_aspect 0.75
  @nominal_width 1000.0

  @typedoc """
  The construct state, unchanged from `Construct.state/0`.

  Painting is not part of it: `draw/2` computes the style's result from
  `:map` and the draw params every time, so nothing style- or
  palette-dependent is ever stored in a frame.
  """
  @type state :: %{
          required(:tiling) => Tiling.t(),
          required(:translations) => [Transform.t()],
          required(:map) => PlanarMap.t(),
          required(:failure) => nil | Construct.reason(),
          optional(atom()) => any()
        }

  @impl true
  @spec slug() :: String.t()
  def slug, do: "styles"

  @impl true
  @spec title() :: String.t()
  def title, do: "Styles"

  @impl true
  def byline, do: "painting a constructed tiling"

  @impl true
  @spec summary() :: String.t()
  def summary, do: "A constructed tiling painted by a render style over a Sanzo Wada palette."

  @impl true
  @spec category() :: atom()
  def category, do: :styles

  @impl true
  @spec params() :: [Param.t()]
  def params do
    [
      %Param{
        name: :tiling,
        type: :enum,
        options: Catalogue.name_options(),
        default: :"8.5",
        doc: "The shipped tiling to construct and paint."
      },
      %Param{
        name: :figure,
        type: :enum,
        options: [:rosette, :star, :none],
        default: :rosette,
        doc: "The figure bound to every regular tile; `none` leaves every tile unbound."
      },
      %Param{
        name: :style,
        type: :enum,
        options: Style.options(),
        default: :filled,
        doc: "The render style that paints the constructed map."
      },
      %Param{
        name: :palette,
        type: :palette,
        options: Palette.options(),
        default: :"253",
        doc: "The Wada colour combination the style's palette roles come from."
      },
      %Param{
        name: :tiles,
        type: :boolean,
        default: false,
        doc: "Draws the faint lattice tile overlay above the figure."
      }
    ]
  end

  @impl true
  @spec initial(map()) :: state()
  def initial(%{tiling: name, figure: figure} = params) do
    tiling = load(name)

    Construct.start(tiling, binder(figure), Construct.patch_region(tiling, cells(params)))
  end

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(%{tiling: name, figure: figure} = params) do
    tiling = load(name)

    Construct.steps(tiling, binder(figure), Construct.patch_region(tiling, cells(params)))
  end

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(%Steps.Frame{state: state}, params) do
    paint = paint_map(params.style, state.map, params.palette)
    {ops, faces} = picture(paint, state, params)
    {:both, ops, rows(state, params, faces, paint)}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(%{tiling: name, figure: figure, style: style, palette: palette} = params) do
    tiling = "Girihelix.Engine.Tilings.Catalogue.load!(" <> inspect(Atom.to_string(name)) <> ")"

    "Girihelix.Engine.Render.Style.paint(" <>
      inspect(style) <>
      ", " <>
      "Girihelix.Engine.Tilings.Construct.construct!(" <>
      tiling <>
      ", " <>
      binder_call(figure) <>
      ", Girihelix.Engine.Tilings.Construct.patch_region(" <>
      tiling <>
      ", " <>
      Integer.to_string(cells(params)) <>
      ")), " <>
      "Girihelix.Engine.Render.Palette.roles!(" <>
      inspect(palette) <>
      ", " <>
      inspect(Style.roles(style)) <>
      "))"
  end

  @impl true
  @spec viewport(map(), [Steps.Frame.t()]) :: Viewport.t()
  def viewport(params, frames) do
    state = frames |> List.last() |> Map.fetch!(:state)
    cell = max(Point.mag(state.tiling.t1), Point.mag(state.tiling.t2))
    pinned(content_centre(state), cells(params) * cell / @canvas_aspect)
  end

  # The window is `width` by `width * aspect` map units, centred on the content
  # and projected at the canvas's nominal width. With no content to centre on,
  # the empty view is what a canvas with no drawing already uses.
  defp pinned(nil, _width), do: Viewport.fit(nil)

  defp pinned({centre_x, centre_y}, width) do
    %Viewport{
      left: centre_x - width / 2.0,
      top: centre_y + width * @canvas_aspect / 2.0,
      width: width,
      scale: @nominal_width / width
    }
  end

  # The centre comes from the constructed map's vertices, never from the painted
  # ops: those carry the tile overlay when it is on, which spans the whole patch
  # and would widen the window to it. An unbound run leaves the map empty, and
  # the structure the frames draw is the fallback.
  defp content_centre(%{map: map} = state) do
    map |> PlanarMap.vertices() |> vertices_centre(map, state)
  end

  defp vertices_centre([], _map, state) do
    state |> Tilings.structure_ops() |> Bounds.of_ops() |> bounds_centre()
  end

  defp vertices_centre(vertices, map, _state) do
    vertices |> Enum.map(&PlanarMap.position!(map, &1)) |> points_centre()
  end

  defp bounds_centre(nil), do: nil

  defp bounds_centre({min_x, min_y, max_x, max_y}), do: {(min_x + max_x) / 2.0, (min_y + max_y) / 2.0}

  defp points_centre([first | rest]) do
    {min_x, min_y, max_x, max_y} =
      Enum.reduce(rest, {first.x, first.y, first.x, first.y}, &extend/2)

    bounds_centre({min_x, min_y, max_x, max_y})
  end

  defp extend(%Point{x: x, y: y}, {min_x, min_y, max_x, max_y}) do
    {min(min_x, x), min(min_y, y), max(max_x, x), max(max_y, y)}
  end

  # A painted result with ops is the picture; frame zero, an empty painting and
  # a retained failure frame all fall back to the shared construct structure.
  # The background is composed beneath the figure and the tile overlay above it,
  # so the lattice reads over the paint in every frame.
  defp picture({:ok, %{background: background, ops: [_ | _] = ops, faces: faces}}, state, params) do
    {List.wrap(background) ++ ops ++ overlay(state, params), faces}
  end

  defp picture(_absent_or_failed, state, params) do
    {Tilings.structure_ops(state) ++ overlay(state, params), nil}
  end

  defp overlay(%{tiling: tiling, translations: translations}, %{tiles: true}) do
    Tilings.tile_ops(tiling, translations)
  end

  defp overlay(_state, _params), do: []

  defp rows(%{tiling: %Tiling{name: name}, map: map} = state, params, faces, paint) do
    [
      {"tiling", name},
      {"figure", Atom.to_string(params.figure)},
      {"style", Atom.to_string(params.style)},
      {"palette", "Wada " <> Atom.to_string(params.palette)},
      {"faces", Figures.integer(faces)},
      {"vertices", Integer.to_string(PlanarMap.num_vertices(map))},
      {"edges", Integer.to_string(PlanarMap.num_edges(map))},
      {"failure", failure(state, paint)}
    ]
  end

  # The construct records its own reason; the draw's painting records its
  # reason beside it. Either is the panel's failure row, and both absent is
  # `none`.
  @spec failure(state(), {:ok, Style.result()} | {:error, term()}) :: String.t()
  defp failure(%{failure: reason}, _paint) when not is_nil(reason), do: failure_name(reason)
  defp failure(_state, {:error, reason}), do: failure_name(reason)
  defp failure(_state, _paint), do: "none"

  defp failure_name(nil), do: "none"
  defp failure_name(reason) when is_atom(reason), do: Atom.to_string(reason)

  # Defensive totality over `Construct.state`'s declared reason, which includes
  # the wrapped-exception tuple even though no current construction step stores
  # it: a future step that does still gets a readable row.
  defp failure_name({:figure_failed, exception}), do: Exception.message(exception)
  defp failure_name(reason), do: inspect(reason)

  # The draw's painting: the style's ops over the welded map, or its reason.
  # Recomputed on every draw, so it never enters a frame.
  defp paint_map(style, map, palette) do
    case Palette.roles(palette, Style.roles(style)) do
      {:ok, roles} -> Style.paint(style, map, roles)
      {:error, reason} -> {:error, reason}
    end
  end

  # The catalogue is trusted local data: `load!/1` is the honest raise.
  @spec load(atom()) :: Tiling.t()
  defp load(name), do: Catalogue.load!(Atom.to_string(name))

  # The run's adaptive probe supplies the span. A plain caller — the exhibit's
  # own tests — passes no `:cells` key and gets the shipped two.
  @spec cells(map()) :: pos_integer()
  defp cells(params), do: Map.get(params, :cells, @patch_cells)

  # One binder per declared figure, delegated so the styled pattern binds its
  # figures exactly as the instancing exhibit does. Private: the exhibit's
  # public surface is exactly the behaviour's callbacks.
  defp binder(figure), do: Instancing.binder(figure)

  defp binder_call(figure), do: Instancing.binder_call(figure)
end
