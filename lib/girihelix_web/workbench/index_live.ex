defmodule GirihelixWeb.Workbench.IndexLive do
  @moduledoc """
  The workbench's front door: every exhibit, grouped by category.

  The page is a directory, not a control. Each entry links to the exhibit's own
  URL, whose query string carries that exhibit's state, so the index itself has
  nothing to keep beyond the registry's grouping.
  """

  use GirihelixWeb, :live_view

  alias GirihelixWeb.Workbench.Registry

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :groups, Registry.grouped())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col gap-8">
        <header class="flex flex-col gap-2">
          <h1 class="text-2xl font-semibold">Workbench</h1>
          <p class="text-sm opacity-70">
            Step through the engine's algorithms one frame at a time.
          </p>
        </header>

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
    </Layouts.app>
    """
  end
end
