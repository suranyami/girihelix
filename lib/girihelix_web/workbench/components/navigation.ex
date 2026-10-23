defmodule GirihelixWeb.Workbench.Components.Navigation do
  @moduledoc """
  The workbench's persistent navigation.

  `rail_drawer/1` is the daisyUI 5 responsive collapsible icon-only drawer that
  wraps the workbench pages: a `div.drawer` with `lg:drawer-open`, a hidden
  `drawer-toggle` checkbox storing the state, the page inside `drawer-content`,
  and the rail in `drawer-side`, with an open button label carrying
  `drawer-button`, `lg:hidden`. The state is checkbox-driven, so the drawer
  opens and closes without JavaScript.

  The rail lists every category as a `menu-title` heading followed by its
  exhibits - titles only, never a title-plus-summary pair. Closed, an entry
  keeps its title's first letter as a badge chip where the icon would be, with
  the title hidden (`is-drawer-close:hidden`) and a tooltip carrying the title;
  the headings hide entirely. The current exhibit's entry is highlighted and
  carries `aria-current="page"`; its category's heading is bold and primary.

  The top navbar's category items live in
  `GirihelixWeb.Layouts.navbar_categories/2`, fed by the same `groups`.
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
    <div class="drawer lg:drawer-open">
      <input id="rail-drawer" type="checkbox" class="drawer-toggle" />
      <div class="drawer-content min-w-0">
        {render_slot(@inner_block)}
        <label
          for="rail-drawer"
          aria-label="open sidebar"
          class="btn btn-square btn-ghost drawer-button fixed bottom-4 left-4 z-10 lg:hidden"
        >
          <.icon name="hero-bars-3" class="size-6" />
        </label>
      </div>

      <div class="drawer-side is-drawer-close:overflow-visible">
        <label for="rail-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <div class="flex min-h-full flex-col items-start bg-base-200 is-drawer-close:w-14 is-drawer-open:w-56">
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
    doc: "a flat rail entry from `entries/2`: `{:heading, label, state}` or `{:exhibit, slug, title, state}`"

  # `menu-title` styles a rail heading and `is-drawer-close:hidden` hides it
  # when the drawer is closed; the active category's heading is bold and
  # primary.
  def rail_entry(%{entry: {:heading, label, :active}} = assigns) do
    assigns = assign(assigns, :label, label)

    ~H"""
    <li class="menu-title is-drawer-close:hidden">
      <span class="font-bold text-primary">{@label}</span>
    </li>
    """
  end

  def rail_entry(%{entry: {:heading, label, :idle}} = assigns) do
    assigns = assign(assigns, :label, label)

    ~H"""
    <li class="menu-title is-drawer-close:hidden">
      <span>{@label}</span>
    </li>
    """
  end

  # The current exhibit's entry is highlighted and carries
  # `aria-current="page"`: deterministic for tests and right for a screen
  # reader. Closed, the chip stands in for the icon and the tooltip carries
  # the title.
  def rail_entry(%{entry: {:exhibit, slug, title, :active}} = assigns) do
    assigns = assign(assigns, :slug, slug)
    assigns = assign(assigns, :title, title)

    ~H"""
    <li>
      <.link
        navigate={~p"/workbench/#{@slug}"}
        class="menu-active bg-primary text-primary-content is-drawer-close:tooltip is-drawer-close:tooltip-right"
        data-tip={@title}
        aria-current="page"
      >
        <span class="badge badge-ghost badge-sm">{String.first(@title)}</span>
        <span class="is-drawer-close:hidden">{@title}</span>
      </.link>
    </li>
    """
  end

  def rail_entry(%{entry: {:exhibit, slug, title, :idle}} = assigns) do
    assigns = assign(assigns, :slug, slug)
    assigns = assign(assigns, :title, title)

    ~H"""
    <li>
      <.link
        navigate={~p"/workbench/#{@slug}"}
        class="is-drawer-close:tooltip is-drawer-close:tooltip-right"
        data-tip={@title}
      >
        <span class="badge badge-ghost badge-sm">{String.first(@title)}</span>
        <span class="is-drawer-close:hidden">{@title}</span>
      </.link>
    </li>
    """
  end

  # Interleaves each category's `menu-title` heading with its exhibits, tagging
  # every entry with its state, so the `rail_entry/1` clauses match on shape:
  # the current exhibit and its category's heading are `:active`; everything
  # else is `:idle`.
  defp entries(groups, active_slug) when is_list(groups), do: Enum.flat_map(groups, &entries(&1, active_slug))

  defp entries({category, exhibits}, active_slug) do
    [
      {:heading, Phoenix.Naming.humanize(category), heading_state(exhibits, active_slug)}
      | Enum.map(exhibits, &{:exhibit, &1.slug(), &1.title(), exhibit_state(&1, active_slug)})
    ]
  end

  defp heading_state(_exhibits, nil), do: :idle
  defp heading_state(exhibits, slug), do: state(member?(exhibits, slug))

  defp member?(exhibits, slug), do: Enum.any?(exhibits, &(&1.slug() == slug))

  defp exhibit_state(_exhibit, nil), do: :idle
  defp exhibit_state(exhibit, slug), do: state(current?(exhibit, slug))

  defp current?(exhibit, slug), do: exhibit.slug() == slug

  defp state(true), do: :active
  defp state(false), do: :idle
end
