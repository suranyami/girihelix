defmodule GirihelixWeb.Workbench.Registry do
  @moduledoc """
  The single list of workbench exhibits, in display order.

  Adding an exhibit is one module implementing `GirihelixWeb.Workbench.Exhibit`
  plus one entry in `@exhibits`. There is no discovery, no naming convention and
  no per-exhibit framework code, so the property test over `exhibits/0` covers
  every exhibit that exists, including the ones later tasks add.

  `grouped/0` keeps a category's position at its **first** appearance in
  `@exhibits`, so display order stays explicit and does not depend on map
  iteration order.
  """

  alias GirihelixWeb.Workbench.Exhibits.Intersect
  alias GirihelixWeb.Workbench.Exhibits.Loose
  alias GirihelixWeb.Workbench.Exhibits.Point
  alias GirihelixWeb.Workbench.Exhibits.Polygon
  alias GirihelixWeb.Workbench.Exhibits.Transform

  @exhibits [Loose, Point, Transform, Intersect, Polygon]

  @doc "Every registered exhibit, in display order."
  @spec exhibits() :: [module()]
  def exhibits, do: @exhibits

  @doc """
  The exhibits grouped by `category/0`, non-empty, in first-seen order.

  Within a group, exhibits keep their `@exhibits` order.
  """
  @spec grouped() :: [{atom(), [module()]}]
  def grouped do
    groups = Enum.group_by(@exhibits, & &1.category())

    @exhibits
    |> Enum.map(& &1.category())
    |> Enum.uniq()
    |> Enum.map(&{&1, Map.fetch!(groups, &1)})
  end

  @doc "The exhibit with `slug`, or `:unknown_exhibit`."
  @spec get(String.t()) :: {:ok, module()} | {:error, :unknown_exhibit}
  def get(slug) when is_binary(slug), do: found(Enum.find(@exhibits, &(&1.slug() == slug)))

  defp found(nil), do: {:error, :unknown_exhibit}
  defp found(exhibit), do: {:ok, exhibit}
end
