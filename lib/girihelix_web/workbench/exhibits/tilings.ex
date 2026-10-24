defmodule GirihelixWeb.Workbench.Exhibits.Tilings do
  @moduledoc """
  The draw ops and panel rows the tiling exhibits share.

  A tiling exhibit draws one tiling's structure: the two translation vectors
  `t1` and `t2` from the origin as guides, closed into the unit cell — the
  parallelogram the generators span — every placed tile as a stroked outline,
  and, once a construction has placed the lattice, a small marker at every
  unit cell's origin. `structure_ops/1` spells that whole composition once, so
  the tiling exhibits that show a construction draw it the same way.

  `rows/1` returns a tiling's own numbers: the name, `t1`, `t2`, features,
  placements.

  This is workbench code, not engine code: it reads `Tiling`'s public API and
  the draw ops, never the engine's internals.
  """

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Op
  alias Girihelix.Engine.Tilings.Feature
  alias Girihelix.Engine.Tilings.PlacedFeature
  alias Girihelix.Engine.Tilings.Tiling
  alias GirihelixWeb.Workbench.Exhibits.Figures
  alias GirihelixWeb.Workbench.Exhibits.Format

  @unit_cell_opts [width: 1.0]
  @marker_radius 2.0
  @marker_opts [opacity: 0.6]

  @doc """
  One stroked polygon per placement, plus the tiling's name, labelled at the
  origin where the translation guides and the unit cell both start.

  Every placement's feature outline is carried through the placement's
  transform, so one feature with several placements draws several polygons.
  """
  @spec outline_ops(Tiling.t()) :: [Op.t()]
  def outline_ops(%Tiling{features: features, placements: placements, name: name}) do
    polygons =
      Enum.map(placements, fn %PlacedFeature{feature_id: feature_id, transform: transform} ->
        {:polygon, placed_points(features, feature_id, transform), :stroke, []}
      end)

    polygons ++ [name_label(name)]
  end

  @doc """
  The static structure every constructed-tiling exhibit draws.

  It composes the translation guides, the cell-origin markers, every placed
  tile's outline and the welded map's own edges, in that order. Frame zero, an
  unbound run and a retained failure frame all draw the first three; only a
  welded map adds the last.
  """
  @spec structure_ops(%{
          tiling: Tiling.t(),
          translations: [Transform.t()],
          map: PlanarMap.t()
        }) :: [Op.t()]
  def structure_ops(%{tiling: tiling, translations: translations, map: map}) do
    translation_ops(tiling) ++
      cell_ops(translations) ++ outline_ops(tiling) ++ Figures.map_ops(map)
  end

  @doc """
  A small marker at every cell origin.

  `translations` are unit-cell translations — `Construct`'s `translations`,
  the lattice over the region — and each carries its cell's origin in
  `(c, f)`. The unit-cell parallelogram itself is drawn by
  `translation_ops/1`, which is where the generators are known.
  """
  @spec cell_ops([Transform.t()]) :: [Op.t()]
  def cell_ops(translations) when is_list(translations) do
    Enum.map(translations, fn %Transform{c: c, f: f} ->
      {:point, {c, f}, @marker_radius, @marker_opts}
    end)
  end

  @doc """
  The two translation-vector guides closed into the unit-cell parallelogram.

  `t1` and `t2` run from the origin as guides, and two more guides — `t1 →
  t1 + t2` and `t2 → t1 + t2` — close the parallelogram around them, so a
  static frame shows the whole cell before a construction has placed
  anything.
  """
  @spec translation_ops(Tiling.t()) :: [Op.t()]
  def translation_ops(%Tiling{t1: t1, t2: t2}) do
    origin = Format.pair(Point.origin())
    far = Format.pair(Point.add(t1, t2))

    [
      {:guide, origin, Format.pair(t1), [width: 1.5]},
      {:guide, origin, Format.pair(t2), [width: 1.5]},
      {:guide, Format.pair(t1), far, @unit_cell_opts},
      {:guide, Format.pair(t2), far, @unit_cell_opts}
    ]
  end

  @doc """
  A tiling's own numbers: its name, its generators, and its counts.

  A `nil` tiling is a frame that has not built one yet: the rows are honest
  placeholders rather than zeros that would read as a result.
  """
  @spec rows(Tiling.t() | nil) :: [{String.t(), String.t()}]
  def rows(nil), do: [{"name", "n/a"}, {"t1", "n/a"}, {"t2", "n/a"}, {"features", "n/a"}, {"placements", "n/a"}]

  def rows(%Tiling{name: name, t1: t1, t2: t2, features: features, placements: placements}) do
    [
      {"name", name},
      {"t1", pair_text(t1)},
      {"t2", pair_text(t2)},
      {"features", Integer.to_string(length(features))},
      {"placements", Integer.to_string(length(placements))}
    ]
  end

  defp placed_points(features, feature_id, transform) do
    features
    |> Enum.find(&(&1.id == feature_id))
    |> Feature.points()
    |> Enum.map(&Transform.apply_to(transform, &1))
    |> Enum.map(&Format.pair/1)
  end

  defp name_label(name), do: {:label, Format.pair(Point.origin()), name, []}

  defp pair_text(%Point{x: x, y: y}), do: "(#{Format.coordinate(x)}, #{Format.coordinate(y)})"
end
