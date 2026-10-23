defmodule GirihelixWeb.Workbench.IndexLive do
  @moduledoc """
  The workbench's front door: every exhibit, grouped by category.

  The page is a directory, not a control. Each entry links to the exhibit's own
  URL, whose query string carries that exhibit's state, so the index itself has
  nothing to keep beyond the registry's grouping. The top navbar and the rail
  drawer, both fed by `Registry.grouped/0`, carry the navigation.
  """

  use GirihelixWeb, :live_view

  import GirihelixWeb.Workbench.Components.Navigation, only: [rail_drawer: 1]

  alias GirihelixWeb.Workbench.Registry
  alias Phoenix.LiveView.Socket

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :groups, Registry.grouped())}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide nav_groups={@groups}>
      <.rail_drawer groups={@groups}>
        <div class="flex flex-col gap-8">
          <section :for={{category, exhibits} <- @groups} class="flex flex-col gap-3">
            <h2 class="text-lg font-semibold">{Phoenix.Naming.humanize(category)}</h2>
            <ul class="flex flex-col gap-2">
              <li :for={exhibit <- exhibits}>
                <.link
                  navigate={~p"/workbench/#{exhibit.slug()}"}
                  class="block rounded-box border border-base-300 p-3 hover:bg-base-200"
                >
                  <span class="block font-semibold">{exhibit.title()}</span>
                  <span class="block text-sm opacity-70">{exhibit.summary()}</span>
                </.link>
              </li>
            </ul>
          </section>
        </div>
      </.rail_drawer>
    </Layouts.app>
    """
  end
end
