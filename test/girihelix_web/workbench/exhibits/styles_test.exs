defmodule GirihelixWeb.Workbench.Exhibits.StylesTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Styles
  alias GirihelixWeb.Workbench.Param

  defp defaults, do: Param.values(Styles.params(), :default)

  defp last_frame(params) do
    params |> Styles.steps() |> Steps.run!(Styles.initial(params)) |> List.last()
  end

  test "identifies itself and declares the five parameters" do
    assert Styles.slug() == "styles"
    assert Styles.category() == :styles
    assert Styles.title() != ""
    assert Styles.summary() != ""

    assert [tiling, figure, style, palette, tiles] = Styles.params()
    assert {tiling.name, tiling.default} == {:tiling, :"8.5"}

    assert {figure.name, figure.options, figure.default} ==
             {:figure, [:rosette, :star, :none], :rosette}

    assert {style.name, style.options, style.default} ==
             {:style, [:plain, :filled, :outline], :filled}

    assert {palette.name, palette.default} == {:palette, :"253"}
    assert length(palette.options) == 348

    assert {tiles.name, tiles.type, tiles.default} == {:tiles, :boolean, false}
  end

  test "the default run ends with a paint step and a painted drawing" do
    params = defaults()

    assert Enum.map(Styles.steps(params), & &1.id) == [:place, :bind, :units, :weld, :paint]

    assert {:both, ops, rows} = Styles.draw(last_frame(params), params)
    assert Enum.any?(ops, &match?({:polygon, _, :fill, _}, &1))
    assert {"tiling", "8.5"} in rows
    assert {"figure", "rosette"} in rows
    assert {"style", "filled"} in rows
    assert {"palette", "Wada 253"} in rows
    assert {"faces", "153"} in rows
    assert {"vertices", "432"} in rows
    assert {"edges", "576"} in rows
    assert {"failure", "none"} in rows
  end

  test "an unbound run paints nothing and still draws the tiling" do
    params = %{defaults() | figure: :none}
    frame = last_frame(params)

    assert {:both, [_ | _], rows} = Styles.draw(frame, params)
    assert {"faces", "n/a"} in rows
    assert {"failure", "no_faces"} in rows
  end

  test "an empty painting falls back to the construct drawing" do
    params = %{defaults() | style: :plain, figure: :none}

    assert {:both, [_ | _], rows} = Styles.draw(last_frame(params), params)
    assert {"style", "plain"} in rows
    assert {"faces", "n/a"} in rows
    # `Plain` over an empty map succeeds with no ops, so the panel falls back to
    # the construct drawing and reports no failure.
    assert {"failure", "none"} in rows
  end

  test "the tile overlay is off by default and sits under the figure" do
    params = defaults()
    assert params.tiles == false

    off = last_frame(params)
    {:both, off_ops, _rows} = Styles.draw(off, params)
    refute Enum.any?(off_ops, &match?({:polygon, _, :fill, [fill: "#2563eb", opacity: 0.12]}, &1))

    on_params = %{params | tiles: true}
    on = last_frame(on_params)
    {:both, on_ops, _rows} = Styles.draw(on, on_params)
    assert Enum.any?(on_ops, &match?({:polygon, _, :fill, [fill: "#2563eb", opacity: 0.12]}, &1))
    assert Enum.any?(on_ops, &match?({:polygon, _, :fill, [fill: "#1b3644"]}, &1))
  end

  test "the overlay composes background, then tile, then figure" do
    params = %{defaults() | style: :plain, tiles: true}
    {:both, [background, tile | _rest], _rows} = Styles.draw(last_frame(params), params)
    assert {:polygon, _, :fill, [fill: _]} = background
    assert {:polygon, _, :fill, [fill: _tint, opacity: 0.12]} = tile
  end

  test "a one-colour palette still paints" do
    params = %{defaults() | palette: :"5"}

    assert {:both, [_ | _], rows} = Styles.draw(last_frame(params), params)
    assert {"palette", "Wada 5"} in rows
    assert {"faces", "153"} in rows
    assert {"failure", "none"} in rows
  end

  test "a triangle tiling in star mode keeps every frame drawable" do
    params = %{defaults() | tiling: :"3-8-12", figure: :star}

    assert {:error, %Steps.Failure{frames: frames}} =
             Steps.run(Styles.steps(params), Styles.initial(params))

    assert frames != []

    for frame <- frames do
      assert {:both, [_ | _], [_ | _]} = Styles.draw(frame, params)
    end
  end

  test "reproduces the painted map with a fully qualified snippet" do
    assert Styles.reproduce(defaults()) ==
             "Girihelix.Engine.Render.Style.paint(:filled, " <>
               "Girihelix.Engine.Tilings.Construct.construct!(" <>
               "Girihelix.Engine.Tilings.Catalogue.load!(\"8.5\"), " <>
               "&GirihelixWeb.Workbench.Exhibits.Instancing.rosette_binder/1, " <>
               "Girihelix.Engine.Tilings.Construct.default_region(" <>
               "Girihelix.Engine.Tilings.Catalogue.load!(\"8.5\"))), " <>
               "Girihelix.Engine.Render.Palette.roles!(:\"253\", [:edge, :darker, :lighter]))"
  end
end
