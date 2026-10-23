defmodule GirihelixWeb.Workbench.Components.Navigation do
  @moduledoc """
  The workbench's persistent navigation.

  `rail_drawer/1` is the workbench's side navbar: a persistent flex column of
  links beside the content, with a hidden checkbox that widens it. The state
  is checkbox-driven - the expander in the top navbar toggles it with a plain
  label, no JavaScript. The `RailDrawer` client hook persists the checkbox
  across live navigations: a first visit defaults open on desktop and closed
  below `lg`, later visits read `localStorage["girihelix:rail-open"]`.

  The rail shows ONLY the active category: a heading for the category followed
  by that category's exhibits, each named by its `title/0` - short by
  construction, since the old title's tag-line now lives in `byline/0`. The
  collapsed rail is `w-36` and the expanded one `w-[21rem]`, both states
  showing the titles. The current exhibit's entry is highlighted and carries
  `aria-current="page"`.

  With no active exhibit (the index), the rail lists the categories
  themselves, each linking its first exhibit. The top navbar's expander and
  category items live in `Layouts.app/1`, fed by the same `groups`.
  """

  use GirihelixWeb, :html

  attr :groups, :list,
    required: true,
    doc: "the `{category, exhibits}` pairs from Registry.grouped/0"

  attr :active_slug, :string, default: nil, doc: "the current exhibit's slug, if any"

  slot :inner_block, required: true

  # The checkbox precedes the rail, so `peer-checked:` widens it when the
  # expander label checks it; content takes the remaining width and never
  # pops over or under the rail.
  def rail_drawer(assigns) do
    assigns = assign(assigns, :entries, entries(assigns.groups, assigns.active_slug))

    ~H"""
    <div id="rail-root" phx-hook="RailDrawer" class="flex min-h-screen min-w-0">
      <input id="rail-drawer" type="checkbox" class="peer hidden" />

      <aside class="flex w-36 shrink-0 flex-col bg-base-200 overflow-x-hidden peer-checked:w-[21rem]">
        <ul class="menu w-full grow">
          <.rail_entry :for={entry <- @entries} entry={entry} />
        </ul>
      </aside>

      <div class="min-w-0 flex-1">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :entry, :any,
    required: true,
    doc: "a flat rail entry from `entries/2`: `{:heading, label, :active}` or `{:exhibit, slug, title, state}`"

  # The active category's heading: bold and primary, and visible in both
  # widths since the "collapsed" rail is wide enough to read it.
  def rail_entry(%{entry: {:heading, label, :active}} = assigns) do
    assigns = assign(assigns, :label, label)

    ~H"""
    <li class="menu-title">
      <span class="text-sm font-bold text-primary">{@label}</span>
    </li>
    """
  end

  # The index rail: one item per category, navigating to that category's first
  # exhibit.
  def rail_entry(%{entry: {:category, label, slug}} = assigns) do
    assigns = assign(assigns, :label, label)
    assigns = assign(assigns, :slug, slug)

    ~H"""
    <li>
      <.link navigate={~p"/workbench/#{@slug}"}>
        <span class="block w-full truncate">{@label}</span>
      </.link>
    </li>
    """
  end

  # The current exhibit's entry is highlighted and carries
  # `aria-current="page"`: deterministic for tests and right for a screen
  # reader. Titles are short by construction now, so the rail shows them whole.
  def rail_entry(%{entry: {:exhibit, slug, title, :active}} = assigns) do
    assigns = assign(assigns, :slug, slug)
    assigns = assign(assigns, :title, title)

    ~H"""
    <li>
      <.link
        navigate={~p"/workbench/#{@slug}"}
        class="menu-active bg-primary text-primary-content"
        aria-current="page"
      >
        <span class="block w-full truncate">{@title}</span>
      </.link>
    </li>
    """
  end

  def rail_entry(%{entry: {:exhibit, slug, title, :idle}} = assigns) do
    assigns = assign(assigns, :slug, slug)
    assigns = assign(assigns, :title, title)

    ~H"""
    <li>
      <.link navigate={~p"/workbench/#{@slug}"}>
        <span class="block w-full truncate">{@title}</span>
      </.link>
    </li>
    """
  end

  # With no active exhibit (the index), the rail lists the categories, each
  # linking its first exhibit. With one, it lists that category's heading and
  # that category's exhibits only. Every entry is precomputed flat so the
  # `rail_entry/1` clauses match on shape: the current exhibit's state is
  # `:active`, everything else `:idle`.
  defp entries(groups, nil), do: Enum.map(groups, &category_entry/1)

  defp entries(groups, active_slug) when is_binary(active_slug) do
    case group_with_slug(groups, active_slug) do
      {category, exhibits} ->
        [
          {:heading, Phoenix.Naming.humanize(category), :active}
          | Enum.map(exhibits, &exhibit_entry(&1, active_slug))
        ]

      nil ->
        []
    end
  end

  defp category_entry({category, exhibits}) do
    {:category, Phoenix.Naming.humanize(category), hd(exhibits).slug()}
  end

  defp exhibit_entry(exhibit, active_slug) do
    {:exhibit, exhibit.slug(), exhibit.title(), exhibit_state(exhibit, active_slug)}
  end

  defp group_with_slug(groups, slug) do
    Enum.find(groups, fn {_category, exhibits} -> Enum.any?(exhibits, &(&1.slug() == slug)) end)
  end

  defp exhibit_state(exhibit, active_slug), do: state(current?(exhibit, active_slug))

  defp current?(exhibit, slug), do: exhibit.slug() == slug

  defp state(true), do: :active
  defp state(false), do: :idle
end
