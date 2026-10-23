defmodule GirihelixWeb.Workbench.IndexLive do
  @moduledoc """
  The workbench's front door: every exhibit, grouped by category.

  The page is a directory, not a control. Each entry links to the exhibit's own
  URL, whose query string carries that exhibit's state, so the index itself has
  nothing to keep beyond the registry's grouping.
  """

  use GirihelixWeb, :live_view

  import GirihelixWeb.Workbench.Components.Navigation, only: [category_nav: 1]

  alias GirihelixWeb.Workbench.Registry
  alias Phoenix.LiveView.Socket

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:groups, Registry.grouped())
     |> assign(:category, nil)}
  end

  @impl true
  @spec handle_params(map(), String.t(), Socket.t()) :: {:noreply, Socket.t()}
  def handle_params(%{"category" => name}, _uri, socket) do
    case Enum.find(Registry.grouped(), fn {category, _exhibits} -> to_string(category) == name end) do
      {category, _exhibits} -> {:noreply, assign(socket, :category, category)}
      nil -> {:noreply, assign(socket, :category, nil)}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, assign(socket, :category, nil)}

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide>
      <div class="flex flex-col gap-8">
        <.category_nav groups={@groups} active={@category} />

        <section
          :for={{category, exhibits} <- visible_groups(@groups, @category)}
          class="flex flex-col gap-3"
        >
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

  # Sections rendered on the index: every group unless the URL scoped one,
  # which keeps its single section.
  defp visible_groups(groups, nil), do: groups

  defp visible_groups(groups, category) do
    case List.keyfind(groups, category, 0) do
      {category, exhibits} -> [{category, exhibits}]
      nil -> groups
    end
  end
end
