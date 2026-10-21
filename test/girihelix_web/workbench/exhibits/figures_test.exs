defmodule GirihelixWeb.Workbench.Exhibits.FiguresTest do
  @moduledoc """
  The shared `Exhibits.Figures` viewport.

  A pinned viewport is only useful if it contains what the exhibit draws, so
  this checks every figure exhibit's final default frame against its own map
  window rather than against a copied literal.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Connect
  alias GirihelixWeb.Workbench.Exhibits.Radial
  alias GirihelixWeb.Workbench.Exhibits.Rosette
  alias GirihelixWeb.Workbench.Exhibits.Scale
  alias GirihelixWeb.Workbench.Exhibits.Star
  alias GirihelixWeb.Workbench.Param

  @aspect 0.75
  @exhibits [Star, Rosette, Scale, Connect, Radial]

  test "every default figure fits its viewport's map window" do
    for exhibit <- @exhibits do
      params = Param.values(exhibit.params(), :default)

      last =
        params
        |> exhibit.steps()
        |> Steps.run!(exhibit.initial(params))
        |> List.last()

      assert {:both, ops, _rows} = exhibit.draw(last, params)
      viewport = exhibit.viewport(params)

      for {x, y} <- drawn_points(ops) do
        assert x >= viewport.left,
               "#{inspect(exhibit)} draws x = #{x} left of the window"

        assert x <= viewport.left + viewport.width,
               "#{inspect(exhibit)} draws x = #{x} right of the window"

        assert y <= viewport.top,
               "#{inspect(exhibit)} draws y = #{y} above the window"

        assert y >= viewport.top - viewport.width * @aspect,
               "#{inspect(exhibit)} draws y = #{y} below the window"
      end
    end
  end

  # Only the drawn geometry: a guide may deliberately run past the figure (the
  # scale exhibit's tip ray is 100 units long), so lines and points are the ops
  # the window has to contain.
  defp drawn_points(ops) do
    Enum.flat_map(ops, fn
      {:line, from, to, _opts} -> [from, to]
      {:point, at, _radius, _opts} -> [at]
      _other -> []
    end)
  end
end
