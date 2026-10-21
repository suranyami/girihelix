defmodule Girihelix.Engine.Render.Bounds do
  @moduledoc """
  An axis-aligned box in map space: `{min_x, min_y, max_x, max_y}`.

  **Points only.** A box spans the positional points of the ops, never their
  decorations. A marker's radius and a label's font size are SVG units, so they
  do not widen the box; the viewport's padding is what keeps such marks off the
  edge.

  `of_ops/1` returns `nil` rather than an empty tuple when there is nothing to
  span, so "no content" is one value a caller matches, not a box of infinities or
  zeros it has to special-case.
  """

  alias Girihelix.Engine.Render.Op

  @type t :: {number(), number(), number(), number()}

  @doc """
  The box spanning every positional point of every op, or `nil` when there is none.

  An unknown op raises through `Op.points/1`, so this function cannot silently
  ignore a malformed drawing.
  """
  @spec of_ops([Op.t()]) :: t() | nil
  def of_ops(ops) do
    ops
    |> Enum.flat_map(&Op.points/1)
    |> span()
  end

  defp span([]), do: nil
  defp span([{x, y} | rest]), do: Enum.reduce(rest, {x, y, x, y}, &extend/2)

  defp extend({x, y}, {min_x, min_y, max_x, max_y}) do
    {min(min_x, x), min(min_y, y), max(max_x, x), max(max_y, y)}
  end

  @doc """
  Grows every side by `amount`.

  A negative `amount` shrinks the box, and enough of it inverts the box rather
  than clamping it; the caller chooses the padding, and `Viewport.fit/2` uses a
  non-negative fraction of the larger extent.
  """
  @spec pad(t(), number()) :: t()
  def pad({min_x, min_y, max_x, max_y}, amount) do
    {min_x - amount, min_y - amount, max_x + amount, max_y + amount}
  end
end
