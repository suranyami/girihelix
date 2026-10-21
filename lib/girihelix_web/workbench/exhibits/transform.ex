defmodule GirihelixWeb.Workbench.Exhibits.Transform do
  @moduledoc """
  An affine transform applied to the unit square or the unit triangle.

  The six scalars are the top two rows of the homogeneous 3x3 matrix:

      [ a  b  c ]
      [ d  e  f ]
      [ 0  0  1 ]

  so a source point `(x, y)` maps to `(a*x + b*y + c, d*x + e*y + f)`. The
  picture draws the source shape as guide lines and the transformed shape as a
  polygon with its vertices marked, so the linear part and the translation can
  be read off together.

  Every row is computed by calling `Girihelix.Engine.Geometry.Transform` — they
  are not transcribed numbers. `determinant/1` is the signed area scale and
  `flips/1` reports when it is negative. At the defaults the transform is the
  translation `(x, y) -> (x + 1, y)`: determinant `1.0`, no flip.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Exhibits.Format
  alias GirihelixWeb.Workbench.Param

  # SVG units, not map units: a marker keeps its screen size as the viewport
  # changes, so this is never projected.
  @vertex_radius 6.0

  @square [{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}, {0.0, 1.0}]
  @triangle [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]

  @impl true
  @spec slug() :: String.t()
  def slug, do: "transform"

  @impl true
  @spec title() :: String.t()
  def title, do: "Transform — an affine map of a shape"

  @impl true
  @spec summary() :: String.t()
  def summary, do: "Six scalars move, scale, rotate, shear or flip the unit square."

  @impl true
  @spec category() :: atom()
  def category, do: :geometry

  @impl true
  @spec params() :: [Param.t()]
  def params do
    [
      scalar(:a, 1.0, "The x-to-x coefficient."),
      scalar(:b, 0.0, "The y-to-x coefficient, the horizontal shear."),
      scalar(:c, 1.0, "The x translation."),
      scalar(:d, 0.0, "The x-to-y coefficient, the vertical shear."),
      scalar(:e, 1.0, "The y-to-y coefficient."),
      scalar(:f, 0.0, "The y translation."),
      %Param{
        name: :shape,
        type: :enum,
        options: [:square, :triangle],
        default: :square,
        doc: "The source shape the transform is applied to."
      }
    ]
  end

  @impl true
  @spec initial(map()) :: map()
  def initial(params), do: params

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(_params) do
    [
      step(
        :build,
        "Read the transform",
        "Takes the six scalars from the parameters; the shape is read when drawing.",
        & &1
      )
    ]
  end

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(_frame, params) do
    transform = transform(params)
    source = source(params)
    image = transformed_points(transform, source)

    ops =
      guide_ops(source) ++
        [{:polygon, image, :stroke, []}] ++
        vertex_ops(image)

    {:both, ops, rows(transform)}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(params) do
    %Transform{a: a, b: b, c: c, d: d, e: e, f: f} = transform(params)

    "Girihelix.Engine.Geometry.Transform.new(" <>
      Enum.map_join([a, b, c, d, e, f], ", ", &Format.coordinate/1) <> ")"
  end

  defp scalar(name, default, doc) do
    %Param{name: name, type: :float, range: -2..2, step: 0.1, default: default, doc: doc}
  end

  defp transform(%{a: a, b: b, c: c, d: d, e: e, f: f}), do: Transform.new(a, b, c, d, e, f)

  defp source(%{shape: :square}), do: @square
  defp source(%{shape: :triangle}), do: @triangle

  defp transformed_points(transform, vertices) do
    Enum.map(vertices, fn {x, y} ->
      %Point{x: x_image, y: y_image} = Transform.apply_coords(transform, x, y)
      {x_image, y_image}
    end)
  end

  # The closed outline of the source shape: every vertex joined to the next,
  # and the last joined back to the first.
  defp guide_ops(vertices) do
    vertices
    |> Enum.zip(Enum.drop(vertices, 1) ++ [hd(vertices)])
    |> Enum.map(fn {from, to} -> {:guide, from, to, []} end)
  end

  defp vertex_ops(points), do: Enum.map(points, &{:point, &1, @vertex_radius, []})

  defp rows(%Transform{} = transform) do
    %Transform{a: a, b: b, c: c, d: d, e: e, f: f} = transform

    [
      {"a", Format.coordinate(a)},
      {"b", Format.coordinate(b)},
      {"c", Format.coordinate(c)},
      {"d", Format.coordinate(d)},
      {"e", Format.coordinate(e)},
      {"f", Format.coordinate(f)},
      {"determinant", Format.coordinate(Transform.determinant(transform))},
      {"flips", to_string(Transform.flips(transform))}
    ]
  end
end
