defmodule GirihelixWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use GirihelixWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :wide, :boolean,
    default: false,
    doc: "use the full window width with a small fixed margin, for the workbench"

  attr :nav_groups, :list,
    default: nil,
    doc:
      "the `{category, exhibits}` pairs from Registry.grouped/0; when passed, the top navbar carries one link per category, to its first exhibit"

  attr :nav_active, :atom,
    default: nil,
    doc: "the active category, highlighted in the top navbar"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar border-b border-base-300 px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href={~p"/"} class="flex w-fit items-center gap-3">
          <span class="text-lg font-semibold tracking-tight">Girihelix</span>
        </a>
      </div>
      <div class="flex-none flex items-center gap-2">
        <.navbar_categories groups={@nav_groups} active={@nav_active} />
      </div>
    </header>

    <main class={main_class(@wide)}>
      <div class={inner_class(@wide)}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  # The workbench's top navbar carries the categories; every other page that
  # uses the layout calls `app/1` without them and gets just the brand.
  defp navbar_categories(%{groups: nil} = assigns), do: ~H""

  defp navbar_categories(assigns) do
    ~H"""
    <nav class="flex items-center gap-1" aria-label="Categories">
      <.link
        :for={{category, exhibits} <- @groups}
        navigate={~p"/workbench/#{hd(exhibits).slug()}"}
        class={category_class(category, @active)}
        aria-current={category_aria(category, @active)}
      >
        {Phoenix.Naming.humanize(category)}
      </.link>
    </nav>
    """
  end

  defp category_class(category, category) when not is_nil(category), do: "btn btn-primary btn-sm"
  defp category_class(_category, _active), do: "btn btn-ghost btn-sm"

  defp category_aria(category, category) when not is_nil(category), do: "page"
  defp category_aria(_category, _active), do: nil

  # The workbench uses the whole window with a small fixed gutter; the rest of
  # the app keeps the narrow centred column.
  defp main_class(true), do: "px-6 py-3 sm:px-8"
  defp main_class(false), do: "px-4 py-20 sm:px-6 lg:px-8"

  defp inner_class(true), do: "space-y-4"
  defp inner_class(false), do: "mx-auto max-w-2xl space-y-4"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
