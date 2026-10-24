defmodule GirihelixWeb.Workbench.Exhibits.Styles do
  @moduledoc """
  One catalogue tiling instanced with a figure, then painted by a render style.

  The exhibit runs `Construct`'s step sequence exactly as `Instancing` does, then
  adds one terminal `:paint` step: the chosen style reads the welded map and the
  four colours the palette resolves to, and returns the draw ops and the number
  of faces it filled. Frame zero and the construct's intermediate frames draw the
  same static structure `Instancing` shows, so a reader can step through the
  construction before the finished picture.

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

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Palette
  alias Girihelix.Engine.Render.Style
  alias Girihelix.Engine.Steps
  alias Girihelix.Engine.Tilings.Catalogue
  alias Girihelix.Engine.Tilings.Construct
  alias Girihelix.Engine.Tilings.Tiling
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Exhibits.Figures
  alias GirihelixWeb.Workbench.Exhibits.Instancing
  alias GirihelixWeb.Workbench.Exhibits.Tilings
  alias GirihelixWeb.Workbench.Param

  @typedoc """
  The construct state with the paint step's outcome beside it.

  `paint` is `nil` before the terminal step, then either the style's result or
  its reason. The construct's own keys are unchanged.
  """
  @type state :: %{
          required(:tiling) => Tiling.t(),
          required(:translations) => [Transform.t()],
          required(:map) => PlanarMap.t(),
          required(:failure) => nil | Construct.reason(),
          required(:paint) => nil | {:ok, Style.result()} | {:error, term()},
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
        type: :enum,
        options: Palette.options(),
        default: :"253",
        doc: "The Wada colour combination the style's four roles come from."
      }
    ]
  end

  @impl true
  @spec initial(map()) :: state()
  def initial(%{tiling: name, figure: figure}) do
    tiling = load(name)
    state = Construct.start(tiling, binder(figure), Construct.default_region(tiling))
    Map.put(state, :paint, nil)
  end

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(%{tiling: name, figure: figure, style: style, palette: palette}) do
    tiling = load(name)

    Construct.steps(tiling, binder(figure), Construct.default_region(tiling)) ++
      [paint_step(style, palette)]
  end

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(%Steps.Frame{state: state}, params) do
    {ops, faces} = picture(state)
    {:both, ops, rows(state, params, faces)}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(%{tiling: name, figure: figure, style: style, palette: palette}) do
    tiling = "Girihelix.Engine.Tilings.Catalogue.load!(" <> inspect(Atom.to_string(name)) <> ")"

    "Girihelix.Engine.Render.Style.paint(" <>
      inspect(style) <>
      ", " <>
      "Girihelix.Engine.Tilings.Construct.construct!(" <>
      tiling <>
      ", " <>
      binder_call(figure) <>
      ", Girihelix.Engine.Tilings.Construct.default_region(" <>
      tiling <>
      ")), " <>
      "Girihelix.Engine.Render.Palette.roles!(" <>
      inspect(palette) <>
      "))"
  end

  # A painted result with ops is the picture; frame zero, an empty painting and
  # a retained failure frame all fall back to the shared construct structure.
  defp picture(state) do
    case Map.get(state, :paint) do
      {:ok, %{ops: [_ | _] = ops, faces: faces}} -> {ops, faces}
      _absent_or_failed -> {Tilings.structure_ops(state), nil}
    end
  end

  defp rows(%{tiling: %Tiling{name: name}, map: map} = state, params, faces) do
    [
      {"tiling", name},
      {"figure", Atom.to_string(params.figure)},
      {"style", Atom.to_string(params.style)},
      {"palette", "Wada " <> Atom.to_string(params.palette)},
      {"faces", Figures.integer(faces)},
      {"vertices", Integer.to_string(PlanarMap.num_vertices(map))},
      {"edges", Integer.to_string(PlanarMap.num_edges(map))},
      {"failure", failure(state)}
    ]
  end

  # The construct records its own reason; the paint step records its reason
  # beside it. Either is the panel's failure row, and both absent is `none`.
  @spec failure(state()) :: String.t()
  defp failure(%{failure: reason}) when not is_nil(reason), do: failure_name(reason)
  defp failure(%{paint: {:error, reason}}), do: failure_name(reason)
  defp failure(_state), do: "none"

  defp failure_name(nil), do: "none"
  defp failure_name(reason) when is_atom(reason), do: Atom.to_string(reason)

  # Defensive totality over `Construct.state`'s declared reason, which includes
  # the wrapped-exception tuple even though no current construction step stores
  # it: a future step that does still gets a readable row.
  defp failure_name({:figure_failed, exception}), do: Exception.message(exception)
  defp failure_name(reason), do: inspect(reason)

  # The paint step: the style's ops over the welded map, or its reason.
  defp paint_step(style, palette) do
    step(
      :paint,
      "paint the map",
      "Runs the chosen style over the constructed map with the palette's four roles; a map the style cannot paint records the reason.",
      fn state -> Map.put(state, :paint, paint_map(style, state.map, palette)) end
    )
  end

  defp paint_map(style, map, palette) do
    case Palette.roles(palette) do
      {:ok, roles} -> Style.paint(style, map, roles)
      {:error, reason} -> {:error, reason}
    end
  end

  # The catalogue is trusted local data: `load!/1` is the honest raise.
  @spec load(atom()) :: Tiling.t()
  defp load(name), do: Catalogue.load!(Atom.to_string(name))

  # One binder per declared figure, delegated so the styled pattern binds its
  # figures exactly as the instancing exhibit does. Private: the exhibit's
  # public surface is exactly the behaviour's callbacks.
  defp binder(figure), do: Instancing.binder(figure)

  defp binder_call(figure), do: Instancing.binder_call(figure)
end
