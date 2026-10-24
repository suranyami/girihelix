defmodule GirihelixWeb.Workbench.Exhibits.InstancingTest do
  @moduledoc """
  The instancing exhibit constructs a tiling with figures and reports verify.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Faces
  alias Girihelix.Engine.Figures.Figure
  alias Girihelix.Engine.Steps
  alias Girihelix.Engine.Tilings.Feature
  alias GirihelixWeb.Workbench.Exhibits.Instancing
  alias GirihelixWeb.Workbench.Param

  test "the instancing exhibit constructs and reports verify" do
    params = Param.values(Instancing.params(), :default)
    last = params |> Instancing.steps() |> Steps.run!(Instancing.initial(params)) |> List.last()

    assert Enum.map(Instancing.steps(params), & &1.id) == [:place, :bind, :units, :weld]
    assert {:both, ops, rows} = Instancing.draw(last, params)
    assert ops != []
    assert {"verify", "ok"} = List.keyfind(rows, "verify", 0)
  end

  test "an unbound run still draws the tiling guides" do
    params = %{Param.values(Instancing.params(), :default) | figure: :none}
    last = params |> Instancing.steps() |> Steps.run!(Instancing.initial(params)) |> List.last()

    assert {:both, [_ | _], rows} = Instancing.draw(last, params)
    assert {"verify", "n/a"} = List.keyfind(rows, "verify", 0)
  end

  test "the star skip is non-degenerate for each tile side count" do
    assert Instancing.star_skip(4) == 3
    assert Instancing.star_skip(5) == 2
    assert Instancing.star_skip(6) == 2
    assert Instancing.star_skip(7) == 3
    assert Instancing.star_skip(8) == 3
    assert Instancing.star_skip(9) == 4
  end

  test "a hexagon star is a hexagram, not three diameters" do
    figure = Instancing.star_binder(%Feature{id: 0, regular: 6, points: []})
    assert {:ok, %{black: black, white: white}} = Faces.extract_faces(Figure.map(figure))
    assert length(black) + length(white) > 3
  end

  test "a triangle tiling in star mode is a failure frame, not a crash" do
    params = %{Param.values(Instancing.params(), :default) | tiling: :"3-8-12", figure: :star}

    assert {:error, %Steps.Failure{frames: frames}} =
             Steps.run(Instancing.steps(params), Instancing.initial(params))

    assert frames != []

    for frame <- frames do
      assert {:both, [_ | _], [_ | _]} = Instancing.draw(frame, params)
    end
  end
end
