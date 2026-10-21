defmodule GirihelixWeb.Workbench.Exhibits.Format do
  @moduledoc """
  The number and point spellings every exhibit's rows and snippets share.

  An exhibit states its numbers as text, and two conventions are easy to get
  subtly different from one exhibit to the next: a measure must read as a float,
  and a draw op takes a point as an `{x, y}` tuple. Keeping both here means the
  panel, the reproduce snippet and the canvas agree by construction.
  """

  alias Girihelix.Engine.Geometry.Point

  @doc """
  Formats a number as the float string a row or snippet shows.

  Integer coordinates are legal in the typed parameter map, but every measure
  reads as a float: `3.0`, never `3`.
  """
  @spec coordinate(number()) :: String.t()
  def coordinate(value), do: value |> Kernel.*(1.0) |> to_string()

  @doc """
  The `{x, y}` tuple a draw op takes, from the point it draws.
  """
  @spec pair(Point.t()) :: {float(), float()}
  def pair(%Point{x: x, y: y}), do: {x, y}
end
