defmodule Girihelix.Engine.Render.Style do
  @moduledoc """
  The contract a paint style implements, and the background `Plain` and
  `Outline` share.

  A style reads a `PlanarMap` and the colours of a `Palette` combination, and
  returns the draw ops that paint the map together with the number of faces it
  filled, or the reason it could not paint the map at all. A style never
  serializes: it emits plain `Op.t()` values and leaves the SVG to
  `Girihelix.Engine.Render.Svg`.

  `options/0` holds the ids in the order a control offers them, `roles/1`
  declares the palette roles each style asks for, and `paint/3` dispatches an id
  to the module behind it, so a caller that holds only an id never names a
  module. `background/2` builds the padded fill op that `Plain` and `Outline`
  return beside their geometry, so their picture is never left floating on the
  view's edge; a style that emits no background returns `nil`. `Filled` covers
  its box with faces instead.
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
  A painted picture: its background (when the style has one), its draw ops in
  order, and how many faces it filled.

  The background is kept apart from the geometry so a caller can paint
  something above it and below the geometry — the tile overlay does — before
  composing the two.

  A style that fills no faces reports `nil` rather than `0`, so a caller can
  tell "this style does not fill" from "this style filled none".
  """
  @type result :: %{background: Op.t() | nil, ops: [Op.t()], faces: non_neg_integer() | nil}

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
  The palette roles the style `id` asks for.

  `:plain` and `:outline` draw one edge colour over a background; `:filled`
  paints the two faces and the boundary.
  """
  @spec roles(id()) :: [atom()]
  def roles(:plain), do: [:edge, :background]
  def roles(:filled), do: [:edge, :darker, :lighter]
  def roles(:outline), do: [:edge, :background]

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
  The filled background op covering `ops`, or `nil` when there is none to draw.

  The fill spans the box around the drawing, grown on every side by two per
  cent of the box's longer side, so the strokes stand clear of the view's edge.
  A drawing with no positions, or one whose positions all coincide, spans
  nothing and has no background.

  The corners run lower-left, lower-right, upper-right, upper-left.
  """
  @spec background([Op.t()], Palette.roles()) :: Op.t() | nil
  def background(ops, %{background: hex}) do
    ops |> Bounds.of_ops() |> background_op(hex)
  end

  defp background_op(nil, _hex), do: nil

  defp background_op({min_x, min_y, max_x, max_y}, _hex) when min_x == max_x and min_y == max_y, do: nil

  defp background_op(box, hex), do: fill_op(box, hex)

  defp fill_op(box, hex) do
    {left, bottom, right, top} = pad(box)

    {:polygon, [{left, bottom}, {right, bottom}, {right, top}, {left, top}], :fill, [fill: hex]}
  end

  defp pad({min_x, min_y, max_x, max_y} = box) do
    Bounds.pad(box, @padding * max(max_x - min_x, max_y - min_y))
  end
end
