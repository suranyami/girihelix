defmodule GirihelixWeb.Workbench.Components.Controls do
  @moduledoc """
  Renders one control per declared parameter and sends their values as one form.

  The form is the whole panel: every input carries its parameter's name, so a
  change sends `phx-change="params"` with all of them, debounced by 200 ms so a
  dragged slider does not flood the LiveView. The LiveView owns what the change
  means; this component owns only the markup.

  A numeric parameter uses a plain `<input type="range">` because
  `CoreComponents.input/1` does not accept `type="range"`. Its bounds come from
  the parameter's integer-backed `:range` and its precision from `:step`, which
  is how a `:float` parameter carries a fractional step over integer bounds.
  The current value is repeated beside the slider, so a clamped value is legible
  without reading the URL.

  A `:boolean` is a checkbox, preceded by a hidden input carrying `"false"`:
  an unchecked checkbox sends nothing, so the hidden value is what makes
  "cleared" reach the server as `false` rather than as an absent parameter. An
  `:enum` uses `<.input type="select">`. Select values are
  strings on the wire, so each value is stringified before it is handed to the
  input; a missing value falls back to the parameter's declared default.

  A `:palette` is an enum on the wire, but its options are colour combinations,
  so it is a `<fieldset>` of radio rows rather than a select: each row shows the
  combination's number and its colours as swatches, inside a scroll container so
  all 348 combinations fit the panel.
  """

  use GirihelixWeb, :html

  alias Girihelix.Engine.Render.Palette
  alias GirihelixWeb.Workbench.Param

  attr :params, :list, required: true, doc: "The exhibit's declared parameters."
  attr :values, :map, required: true, doc: "The current value of every parameter."

  @spec controls(map()) :: Phoenix.LiveView.Rendered.t()
  def controls(assigns) do
    ~H"""
    <form id="controls" phx-change="params" phx-debounce="200" class="flex flex-col gap-4">
      <.control
        :for={param <- @params}
        param={param}
        value={Map.get(@values, param.name, param.default)}
      />
    </form>
    """
  end

  attr :param, Param, required: true
  attr :value, :any, required: true

  defp control(%{param: %Param{type: type}} = assigns) when type in [:integer, :float] do
    ~H"""
    <div>
      <.control_label param={@param} />
      <div class="flex items-center gap-3">
        <input
          type="range"
          id={@param.name}
          name={@param.name}
          min={@param.range.first}
          max={@param.range.last}
          step={@param.step}
          value={@value}
          class="range range-sm"
        />
        <span class="text-sm tabular-nums">{@value}</span>
      </div>
    </div>
    """
  end

  defp control(%{param: %Param{type: :boolean}} = assigns) do
    ~H"""
    <div>
      <.control_label param={@param} />
      <input type="hidden" name={@param.name} value="false" />
      <input
        type="checkbox"
        id={@param.name}
        name={@param.name}
        value="true"
        checked={@value}
        class="checkbox checkbox-sm"
      />
    </div>
    """
  end

  defp control(%{param: %Param{type: :enum} = param} = assigns) do
    assigns = assign(assigns, :options, Enum.map(param.options, &{to_string(&1), to_string(&1)}))

    ~H"""
    <div>
      <.control_label param={@param} />
      <.input
        type="select"
        id={@param.name}
        name={@param.name}
        value={to_string(@value)}
        options={@options}
      />
    </div>
    """
  end

  defp control(%{param: %Param{type: :palette} = param} = assigns) do
    assigns = assign(assigns, :combinations, Enum.map(param.options, &{&1, colours(&1)}))

    ~H"""
    <fieldset>
      <legend class="label mb-1">
        <span class="font-semibold">{@param.name}</span>
        <span :if={@param.doc} class="opacity-70">{@param.doc}</span>
      </legend>
      <div class="max-h-72 overflow-y-auto">
        <label
          :for={{option, colours} <- @combinations}
          class="flex cursor-pointer items-center gap-2 rounded px-1 py-0.5 hover:bg-base-200"
        >
          <input
            type="radio"
            name={@param.name}
            value={to_string(option)}
            checked={option == @value}
            class="radio radio-xs"
          />
          <span class="w-8 text-sm tabular-nums">{to_string(option)}</span>
          <span
            :for={colour <- colours}
            class="h-3 w-3 rounded-sm"
            style={"background-color: #{colour.hex}"}
          ></span>
        </label>
      </div>
    </fieldset>
    """
  end

  # The palette's options are ids of the trusted local dataset, so a colour list
  # is always present; an option outside it renders as a row with no swatches
  # rather than raising.
  defp colours(option) do
    case Palette.combination(option) do
      {:ok, colours} -> colours
      {:error, :unknown_combination} -> []
    end
  end

  attr :param, Param, required: true

  defp control_label(assigns) do
    ~H"""
    <label for={@param.name} class="label mb-1">
      <span class="font-semibold">{@param.name}</span>
      <span :if={@param.doc} class="opacity-70">{@param.doc}</span>
    </label>
    """
  end
end
