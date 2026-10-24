defmodule Girihelix.Engine.Render.Style do
  @moduledoc """
  The contract a paint style implements, and the background every style shares.

  A style reads a `PlanarMap` and the four colours of a `Palette` combination,
  and returns the draw ops that paint the map together with the number of faces
  it filled, or the reason it could not paint the map at all. A style never
  serializes: it emits plain `Op.t()` values and leaves the SVG to
  `Girihelix.Engine.Render.Svg`.

  `options/0` holds the ids in the order a control offers them, and `paint/3`
  dispatches an id to the module behind it, so a caller that holds only an id
  never names a module. `background/2` builds the padded fill op that `Plain`
  and `Outline` emit behind their geometry, so their picture is never left
  floating on the view's edge. `Filled` covers its box with faces instead.
  """

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Bounds
  alias Girihelix.Engine.Render.Op
  alias Girihelix.Engine.Render.Palette
  alias Girihelix.Engine.Render.Styles.Filled
  alias Girihelix.Engine.Render.Styles.Outline
  alias Girihelix.Engine.Render.Styles.Plain

  @padding 0.02

  @type id :: :plain | :filled | :outline
  @type reason :: :filling_conflict | :no_faces

  @typedoc """
  A painted picture: its draw ops in order, and how many faces it filled.

  A style that fills no faces reports `nil` rather than `0`, so a caller can
  tell "this style does not fill" from "this style filled none".
  """
  @type result :: %{ops: [Op.t()], faces: non_neg_integer() | nil}

  @doc """
  Paints `map` with the colours `roles` names, or reports why it could not.
  """
  @callback paint(PlanarMap.t(), Palette.roles()) :: {:ok, result()} | {:error, reason()}

  @doc """
  The style ids in control order: `:plain`, then `:filled`, then `:outline`.
  """
  @spec options() :: [id()]
  def options, do: [:plain, :filled, :outline]

  @doc """
  Paints `map` with the style `id` names.

  The result is that style's own: its ops and face count, or its reason for
  failing.
  """
  @spec paint(id(), PlanarMap.t(), Palette.roles()) :: {:ok, result()} | {:error, reason()}
  def paint(:plain, map, roles), do: Plain.paint(map, roles)
  def paint(:filled, map, roles), do: Filled.paint(map, roles)
  def paint(:outline, map, roles), do: Outline.paint(map, roles)

  @doc """
  A `Point` as the `{x, y}` pair an op spells a coordinate with.
  """
  @spec pair(Point.t()) :: Op.point()
  def pair(%Point{x: x, y: y}), do: {x, y}

  @doc """
  `ops` with a filled background op prepended.

  The fill spans the box around the drawing, grown on every side by two per
  cent of the box's longer side, so the strokes stand clear of the view's edge.
  A drawing with no positions spans nothing and is returned unchanged.

  The corners run lower-left, lower-right, upper-right, upper-left.
  """
  @spec background([Op.t()], Palette.roles()) :: [Op.t()]
  def background(ops, %{background: hex}) do
    ops |> Bounds.of_ops() |> fill_behind(ops, hex)
  end

  defp fill_behind(nil, ops, _hex), do: ops
  defp fill_behind(box, ops, hex), do: [fill_op(box, hex) | ops]

  defp fill_op(box, hex) do
    {left, bottom, right, top} = pad(box)

    {:polygon, [{left, bottom}, {right, bottom}, {right, top}, {left, top}], :fill, [fill: hex]}
  end

  defp pad({min_x, min_y, max_x, max_y} = box) do
    Bounds.pad(box, @padding * max(max_x - min_x, max_y - min_y))
  end
end
