defmodule GirihelixWeb.Workbench.Components.Navigation do
  @moduledoc """
  The workbench's persistent navigation.

  Two pieces, both category-driven from `GirihelixWeb.Workbench.Registry.grouped/0`,
  so a new category (Plan 5's `:styles`, say) appears as a navbar item on its own:

    * `category_nav/1` — one link per category, carried as `?category=<name>`
      on the index, with the active category highlighted. Exhibit pages bind
      the active category to their exhibit.
    * `exhibit_rail/1` — the active category's exhibit titles, one link each.
      Nothing else: the title-byline and description live on the exhibit page
      itself, under its header.

  The rail is `hidden lg:block` — a dev tool's nav is not worth the fold-out
  plumbing on a phone, and the category navbar still carries the way there.
  """

  use GirihelixWeb, :html

  attr :groups, :list,
    required: true,
    doc: "the `{category, exhibits}` pairs from Registry.grouped/0"

  attr :active, :atom, default: nil, doc: "the category to highlight, if any"

  def category_nav(assigns) do
    ~H"""
    <nav class="border-b border-base-300" aria-label="Categories">
      <ul class="flex flex-wrap gap-1 py-1">
        <li :for={{category, _exhibits} <- @groups}>
          <.link
            navigate={~p"/workbench?category=#{category}"}
            class={nav_class(category, @active)}
          >
            {Phoenix.Naming.humanize(category)}
          </.link>
        </li>
      </ul>
    </nav>
    """
  end

  defp nav_class(category, active)

  defp nav_class(category, category), do: "btn btn-primary btn-sm"
  defp nav_class(_category, _active), do: "btn btn-ghost btn-sm"

  attr :exhibits, :list, required: true, doc: "the active category's exhibit modules"
  attr :active_slug, :string, default: nil, doc: "the exhibit whose page the rail sits on"

  def exhibit_rail(assigns) do
    ~H"""
    <nav aria-label="Exhibits">
      <ul class="flex flex-col gap-1">
        <li :for={exhibit <- @exhibits}>
          <.link
            navigate={~p"/workbench/#{exhibit.slug()}"}
            class={rail_class(exhibit.slug(), @active_slug)}
          >
            {exhibit.title()}
          </.link>
        </li>
      </ul>
    </nav>
    """
  end

  defp rail_class(slug, active_slug)

  defp rail_class(slug, slug), do: "font-semibold"
  defp rail_class(_slug, _active_slug), do: "opacity-70 hover:opacity-100"
end
