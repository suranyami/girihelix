defmodule GirihelixWeb.Workbench.Exhibits.StylesTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Viewport
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
    assert {"faces", "1037"} in rows
    assert {"vertices", "2928"} in rows
    assert {"edges", "3904"} in rows
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

  test "the tile overlay is off by default and sits over the figure" do
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

  test "the overlay composes background, then figure, then tile" do
    params = %{defaults() | style: :plain, tiles: true}

    {:both, [background | rest], _rows} = Styles.draw(last_frame(params), params)

    assert {:polygon, _, :fill, [fill: _]} = background

    # Every figure op precedes the overlay: strip `Plain`'s lines, then the
    # first tile pair, and assert nothing but tile polygons follow.
    assert {[_ | _] = figure, [tile, tile_stroke | tail]} =
             Enum.split_while(rest, &match?({:line, _, _, _}, &1))

    assert {:line, _, _, _} = List.first(figure)
    assert {:polygon, _, :fill, [fill: _tint, opacity: 0.12]} = tile
    assert {:polygon, _, :stroke, [stroke: _, width: 0.75, opacity: 0.5]} = tile_stroke
    assert Enum.all?(tail, &match?({:polygon, _, _, _}, &1))
  end

  test "a one-colour palette still paints" do
    params = %{defaults() | palette: :"5"}

    assert {:both, [_ | _], rows} = Styles.draw(last_frame(params), params)
    assert {"palette", "Wada 5"} in rows
    assert {"faces", "1037"} in rows
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

  test "the viewport shows two cells and is centred on the content" do
    params = defaults()
    frames = Steps.run!(Styles.steps(params), Styles.initial(params))
    viewport = Styles.viewport(params, frames)
    state = List.last(frames).state
    cell = max(Point.mag(state.tiling.t1), Point.mag(state.tiling.t2))

    assert_in_delta viewport.width, 2.0 * cell / 0.75, 1.0e-9
    assert_in_delta viewport.scale, 1000.0 / viewport.width, 1.0e-9
  end

  test "the windowed interior is periodic in both lattice directions" do
    for tiling <- [:"8.5", :"6.5 flower"] do
      params = %{defaults() | tiling: tiling}
      frames = Steps.run!(Styles.steps(params), Styles.initial(params))
      state = List.last(frames).state
      viewport = Styles.viewport(params, frames)
      map = state.map

      vertices =
        for vertex <- PlanarMap.vertices(map) do
          point = PlanarMap.position!(map, vertex)
          {rounded_point(point), point}
        end

      positions = MapSet.new(vertices, fn {rounded, _point} -> rounded end)

      window =
        {viewport.left, viewport.top - viewport.width * 0.75, viewport.left + viewport.width, viewport.top}

      inside =
        Enum.filter(vertices, fn {rounded, _point} ->
          {x, y} = rounded
          {min_x, min_y, max_x, max_y} = window
          x > min_x and x < max_x and y > min_y and y < max_y
        end)

      assert inside != []

      # The rounded position locates the vertex; the target is the exact
      # position translated and rounded once. Translating the already-rounded
      # position would double-round and can miss a counterpart that is there.
      for {_rounded, point} <- inside, axis <- [state.tiling.t1, state.tiling.t2] do
        target = rounded_point({point.x + axis.x, point.y + axis.y})
        assert MapSet.member?(positions, target)
      end
    end
  end

  test "a failed run still pins a viewport" do
    params = %{defaults() | tiling: :"3-8-12", figure: :star}

    assert {:error, %Steps.Failure{frames: frames}} =
             Steps.run(Styles.steps(params), Styles.initial(params))

    assert %Viewport{} = Styles.viewport(params, frames)
  end

  test "reproduces the painted map with a fully qualified snippet" do
    assert Styles.reproduce(defaults()) ==
             "Girihelix.Engine.Render.Style.paint(:filled, " <>
               "Girihelix.Engine.Tilings.Construct.construct!(" <>
               "Girihelix.Engine.Tilings.Catalogue.load!(\"8.5\"), " <>
               "&GirihelixWeb.Workbench.Exhibits.Instancing.rosette_binder/1, " <>
               "Girihelix.Engine.Tilings.Construct.patch_region(" <>
               "Girihelix.Engine.Tilings.Catalogue.load!(\"8.5\"), 2)), " <>
               "Girihelix.Engine.Render.Palette.roles!(:\"253\", [:edge, :darker, :lighter]))"
  end

  defp rounded_point(%Point{x: x, y: y}), do: {Float.round(x, 6), Float.round(y, 6)}
  defp rounded_point({x, y}), do: {Float.round(x, 6), Float.round(y, 6)}
end
