defmodule Girihelix.Engine.Tilings.Tiling do
  @moduledoc """
  A whole tiling: its name, its two lattice generators, its tiles, and where
  they are placed.

  This is the value behind Taprats' tiling `tiling` class: `t1` and `t2` span
  the translational unit cell — the parallelogram `unit_cell/1` spells out — and
  `features` with `placements` describe what repeats under those translations.
  A later task parses `.tiling` files into this struct; meanwhile every field is
  a plain value, so `new/1` is total and returns the struct directly.

  `placements_for/2` answers the one question the consumers of a tiling ask:
  which placements carry a given tile.
  """

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.Tilings.Feature
  alias Girihelix.Engine.Tilings.PlacedFeature

  @enforce_keys [:name, :t1, :t2, :features, :placements]
  defstruct [:name, :description, :author, :t1, :t2, :features, :placements]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          author: String.t() | nil,
          t1: Point.t(),
          t2: Point.t(),
          features: [Feature.t()],
          placements: [PlacedFeature.t()]
        }

  @doc """
  Builds a tiling from a keyword list.

  `name`, `t1`, `t2`, `features` and `placements` are required (enforced by the
  struct); `description` and `author` default to `nil`.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.get(opts, :description),
      author: Keyword.get(opts, :author),
      t1: Keyword.fetch!(opts, :t1),
      t2: Keyword.fetch!(opts, :t2),
      features: Keyword.fetch!(opts, :features),
      placements: Keyword.fetch!(opts, :placements)
    }
  end

  @doc """
  The translational unit cell, in order: the origin, `t1`, `t1 + t2`, and `t2` —
  the parallelogram the two generators span.
  """
  @spec unit_cell(t()) :: [Point.t()]
  def unit_cell(%__MODULE__{t1: t1, t2: t2}), do: [Point.origin(), t1, Point.add(t1, t2), t2]

  @doc """
  The transforms of every placement whose `feature_id` is `feature_id`, in the
  order the tiling stores them.
  """
  @spec placements_for(t(), integer()) :: [Transform.t()]
  def placements_for(%__MODULE__{placements: placements}, feature_id) do
    placements
    |> Enum.filter(&matches(&1, feature_id))
    |> Enum.map(fn %PlacedFeature{transform: transform} -> transform end)
  end

  defp matches(%PlacedFeature{feature_id: id}, feature_id), do: id == feature_id
end
