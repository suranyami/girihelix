defmodule Girihelix.Engine.Render.Viewport do
  @moduledoc """
  The map-space window a drawing is viewed through, and its projection to SVG.

  A viewport is stored in four scalars rather than as a box: `left` and `top` are
  the map coordinates of the view's **top-left** corner, `width` is its map-space
  width, and `scale` is SVG units per map unit. The height is not stored; it is
  always `width * aspect`, and the aspect is passed to `view_box/2` because the
  serializer must agree with the aspect the caller framed with. Keeping four
  numbers rather than seven also makes a viewport a literal a test can write.

  **The y axis flips.** Map space is y-up and SVG is y-down. `project/2` measures
  y downward from `top`, so the view's top edge projects to SVG y = 0 and its
  bottom edge to `width * aspect * scale`.

  **`fit/2` frames, it does not crop.** The view is built to contain the padded
  bounds at the requested aspect, widening the horizontal axis when the aspect is
  wider than the content. Content is centred, so the bounds sit centrally in the
  view rather than against an edge. A viewport never changes the drawing; it only
  chooses what the serializer sees.
  """

  alias Girihelix.Engine.Render.Bounds
  alias Girihelix.Engine.Render.Op

  @default_padding 0.1
  @default_aspect 0.75
  @default_scale 1.0

  # The empty view is a fixed square centred on the origin, so a drawing with no
  # points still produces a stable SVG canvas.
  @empty_width 2.0

  @enforce_keys [:left, :top, :width, :scale]
  defstruct [:left, :top, :width, :scale]

  @type t :: %__MODULE__{left: float(), top: float(), width: float(), scale: float()}

  @doc """
  Frames `bounds` (or an empty drawing) at the given options.

  Options:

    * `:padding` — a fraction of the larger extent, added to every side;
      default `#{@default_padding}`.
    * `:aspect` — height divided by width, and therefore greater than zero;
      default `#{@default_aspect}`.
    * `:scale` — SVG units per map unit; default `#{@default_scale}`.

  A bound with no extent at all — a single point, or only a label — becomes a
  `2.0` by `2.0` box centred on it before padding, so the view is never
  zero-width. `nil` bounds give the fixed empty view,
  `%Viewport{left: -1.0, top: 1.0, width: 2.0, scale: scale}`; only `:scale`
  applies to it, since there is no content to pad or frame.
  """
  @spec fit(Bounds.t() | nil, keyword()) :: t()
  def fit(bounds, opts \\ [])

  def fit(nil, opts) do
    %__MODULE__{
      left: -@empty_width / 2.0,
      top: @empty_width / 2.0,
      width: @empty_width,
      scale: option(opts, :scale, @default_scale)
    }
  end

  def fit(bounds, opts) do
    padding = option(opts, :padding, @default_padding)
    aspect = option(opts, :aspect, @default_aspect)
    {min_x, min_y, max_x, max_y} = widen(bounds)
    pad = max(max_x - min_x, max_y - min_y) * padding
    padded_width = max_x - min_x + 2.0 * pad
    padded_height = max_y - min_y + 2.0 * pad
    view_width = max(padded_width, padded_height / aspect)
    centre_x = (min_x + max_x) / 2.0
    centre_y = (min_y + max_y) / 2.0

    %__MODULE__{
      left: centre_x - view_width / 2.0,
      top: centre_y + view_width * aspect / 2.0,
      width: view_width,
      scale: option(opts, :scale, @default_scale)
    }
  end

  # A box with no width and no height would give a zero-width view; widen it to a
  # fixed square around the degenerate point, then pad as usual.
  defp widen({x, y, x, y}), do: {x - 1.0, y - 1.0, x + 1.0, y + 1.0}
  defp widen(bounds), do: bounds

  # Multiplying by 1.0 pins the number options to floats, so a viewport built
  # from integer options still has the float fields its type promises.
  defp option(opts, key, default), do: Keyword.get(opts, key, default) * 1.0

  @doc """
  Projects a map-space point to SVG coordinates.

  Translation then scaling, with y flipped about `top`:
  `{(x - left) * scale, (top - y) * scale}`. The result is in SVG user units,
  y-down, and ready for the serializer to round and print.
  """
  @spec project(t(), Op.point()) :: {float(), float()}
  def project(%__MODULE__{left: left, top: top, scale: scale}, {x, y}) do
    {(x - left) * scale, (top - y) * scale}
  end

  @doc """
  The SVG `viewBox` for this viewport at `aspect`.

  `{0.0, 0.0, width * scale, width * aspect * scale}`. The caller passes the
  same aspect it framed with; the viewport does not store it, so a mismatched
  aspect here is a stretched drawing, not an error.
  """
  @spec view_box(t(), number()) :: {float(), float(), float(), float()}
  def view_box(%__MODULE__{width: width, scale: scale}, aspect) do
    {0.0, 0.0, width * scale, width * aspect * scale}
  end
end
