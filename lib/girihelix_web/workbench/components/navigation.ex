defmodule GirihelixWeb.Workbench.Components.Navigation do
  @moduledoc """
  The workbench's persistent navigation.

  `rail_drawer/1` is the daisyUI 5 responsive collapsible icon-only drawer,
  drawn by `GirihelixWeb.Layouts.app/1` when that receives `nav_groups`: a
  `div.drawer` with `lg:drawer-open`, a hidden `drawer-toggle` checkbox storing
  the state, the header and main inside `drawer-content`, and the rail in
  `drawer-side`. The drawer opens and closes with checkboxes and labels only -
  no JavaScript. On desktop the rail starts condensed and the expander button
  in the top navbar (a `drawer-button` label) widens it; on a phone the same
  label opens it over the page.

  The rail shows ONLY the active category: a `menu-title` heading for the
  category followed by its exhibits - titles only, never a title-plus-summary
  pair. The condensed rail keeps those titles legible (`is-drawer-close:w-24`)
  rather than reducing them to chips, so long ones truncate instead. The current
  exhibit's entry is highlighted and carries `aria-current="page"`; its
  category's heading is bold and primary. With no active exhibit (the index),
  the rail lists the categories themselves, each linking its first exhibit.

  The top navbar's expander and category items live in `Layouts.app/1`, fed by
  the same `groups`.
  """

  use GirihelixWeb, :html

  attr :groups, :list,
    required: true,
    doc: "the `{category, exhibits}` pairs from Registry.grouped/0"

  attr :active_slug, :string, default: nil, doc: "the current exhibit's slug, if any"

  slot :inner_block, required: true

  def rail_drawer(assigns) do
    assigns = assign(assigns, :entries, entries(assigns.groups, assigns.active_slug))

    ~H"""
    <div class="drawer min-w-0 lg:drawer-open">
      <input id="rail-drawer" type="checkbox" class="drawer-toggle" />
      <div class="drawer-content min-w-0">
        {render_slot(@inner_block)}
      </div>

      <div class="drawer-side">
        <label for="rail-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <div class="flex min-h-full flex-col bg-base-200 is-drawer-close:w-24 is-drawer-open:w-56">
          <ul class="menu w-full grow">
            <.rail_entry :for={entry <- @entries} entry={entry} />
          </ul>
        </div>
      </div>
    </div>
    """
  end

  attr :entry, :any,
    required: true,
    doc: "a flat rail entry from `entries/2`: `{:heading, label, :active}` or `{:exhibit, slug, title, state}`"

  # The active category's heading: `menu-title` styles it and hides it when the
  # drawer is closed; it is bold and primary.
  def rail_entry(%{entry: {:heading, label, :active}} = assigns) do
    assigns = assign(assigns, :label, label)

    ~H"""
    <li class="menu-title is-drawer-close:hidden">
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
  # reader.
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
        <span class="block w-full truncate" data-rail-label="short">{@title}</span>
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
        <span class="block w-full truncate" data-rail-label="short">{@title}</span>
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
