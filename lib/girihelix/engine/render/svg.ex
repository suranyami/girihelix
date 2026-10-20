defmodule Girihelix.Engine.Render.Svg do
  @moduledoc """
  Serializes draw ops to an SVG document.

  The serializer is the only place that turns map-space geometry into SVG text.
  It projects every positional point through the given `Viewport`, but it never
  projects a `:point`'s radius or a `:label`'s font size: those are SVG units and
  keep their screen size as the view changes.

  **One element per op, in order.** Each op becomes one child of the root, with
  its attributes in a fixed order so a golden file can compare whole strings.
  Options are validated per op; a key an op does not accept, or an op the
  vocabulary does not know, raises `ArgumentError` rather than being dropped, so
  a misspelt option cannot silently render the default.

  **Numbers.** Every measurement is rounded to four decimal places and printed
  with `to_string/1`, so `1` becomes `"1.0"` and floating-point noise does not
  reach the output.
  """

  alias Girihelix.Engine.Render.Op
  alias Girihelix.Engine.Render.Viewport

  @default_aspect 0.75
  @default_stroke "currentColor"
  @default_width 1.0
  @default_dash "4 4"
  @default_font_size 12.0

  @line_options [:stroke, :width, :dash, :opacity]
  @polygon_options [:fill, :stroke, :width, :dash, :opacity]
  @point_options [:fill, :stroke, :width, :opacity]
  @label_options [:fill, :opacity]

  @doc """
  Renders `ops` inside an SVG root framed by `viewport`.

  Options:

    * `:aspect` — height divided by width of the view; default `#{@default_aspect}`.
      Pass the same aspect the viewport was fitted with.
    * `:class` — an optional class attribute on the root element.
  """
  @spec render([Op.t()], Viewport.t(), keyword()) :: String.t()
  def render(ops, %Viewport{} = viewport, opts \\ []) do
    aspect = Keyword.get(opts, :aspect, @default_aspect) * 1.0

    view_box =
      viewport |> Viewport.view_box(aspect) |> Tuple.to_list() |> Enum.map_join(" ", &number/1)

    class = Keyword.get(opts, :class)

    root(view_box, class) <>
      Enum.map_join(ops, "", &element(&1, viewport)) <>
      "</svg>"
  end

  # The class is optional; the two heads keep that choice out of the body.
  defp root(view_box, nil) do
    ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="#{view_box}">)
  end

  defp root(view_box, class) do
    ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="#{view_box}" class="#{escape(to_string(class))}">)
  end

  defp element({:line, from, to, opts}, viewport) do
    line(from, to, opts, Keyword.get(opts, :dash), viewport)
  end

  defp element({:guide, from, to, opts}, viewport) do
    line(from, to, opts, Keyword.get(opts, :dash, @default_dash), viewport)
  end

  defp element({:polygon, vertices, :fill, opts}, viewport) do
    polygon(vertices, viewport, opts, Keyword.get(opts, :fill, @default_stroke), "none")
  end

  defp element({:polygon, vertices, :stroke, opts}, viewport) do
    polygon(vertices, viewport, opts, "none", Keyword.get(opts, :stroke, @default_stroke))
  end

  defp element({:point, at, radius, opts}, viewport) do
    validate!(opts, @point_options)
    {cx, cy} = Viewport.project(viewport, at)

    tag("circle", [
      {"cx", number(cx)},
      {"cy", number(cy)},
      {"r", number(radius)},
      {"fill", Keyword.get(opts, :fill, @default_stroke)},
      {"stroke", Keyword.get(opts, :stroke)},
      {"stroke-width", optional_number(opts, :width)},
      {"opacity", optional_number(opts, :opacity)}
    ])
  end

  defp element({:label, at, text, opts}, viewport) do
    validate!(opts, @label_options)
    {x, y} = Viewport.project(viewport, at)

    open_tag("text", [
      {"x", number(x)},
      {"y", number(y)},
      {"fill", Keyword.get(opts, :fill, @default_stroke)},
      {"font-size", number(@default_font_size)},
      {"opacity", optional_number(opts, :opacity)}
    ]) <> escape(text) <> "</text>"
  end

  defp element(op, _viewport), do: raise(ArgumentError, "unknown draw op: #{inspect(op)}")

  defp line(from, to, opts, dash, viewport) do
    validate!(opts, @line_options)
    {x1, y1} = Viewport.project(viewport, from)
    {x2, y2} = Viewport.project(viewport, to)

    tag("line", [
      {"x1", number(x1)},
      {"y1", number(y1)},
      {"x2", number(x2)},
      {"y2", number(y2)},
      {"stroke", Keyword.get(opts, :stroke, @default_stroke)},
      {"stroke-width", number(Keyword.get(opts, :width, @default_width))},
      {"stroke-dasharray", dash},
      {"opacity", optional_number(opts, :opacity)}
    ])
  end

  defp polygon(vertices, viewport, opts, fill, stroke) do
    validate!(opts, @polygon_options)

    points =
      Enum.map_join(vertices, " ", fn point ->
        point_string(Viewport.project(viewport, point))
      end)

    tag("polygon", [
      {"points", points},
      {"fill", fill},
      {"stroke", stroke},
      {"stroke-width", number(Keyword.get(opts, :width, @default_width))},
      {"stroke-dasharray", Keyword.get(opts, :dash)},
      {"opacity", optional_number(opts, :opacity)}
    ])
  end

  defp point_string({x, y}), do: "#{number(x)},#{number(y)}"

  defp validate!(opts, allowed) do
    opts
    |> Keyword.keys()
    |> Enum.find(&(&1 not in allowed))
    |> unknown_option()
  end

  defp unknown_option(nil), do: :ok
  defp unknown_option(key), do: raise(ArgumentError, "unknown draw option: #{inspect(key)}")

  defp optional_number(opts, key) do
    opts
    |> Keyword.get(key)
    |> maybe_number()
  end

  defp maybe_number(nil), do: nil
  defp maybe_number(value), do: number(value)

  # A fixed attribute order, with absent (nil) attributes dropped, so an op's
  # output depends only on its data and not on the order its options were given.
  defp tag(name, attributes), do: "<" <> name <> " " <> attributes(attributes) <> "/>"

  defp open_tag(name, attributes), do: "<" <> name <> " " <> attributes(attributes) <> ">"

  defp attributes(pairs) do
    pairs
    |> Enum.reject(fn {_name, value} -> is_nil(value) end)
    |> Enum.map_join(" ", fn {name, value} -> ~s(#{name}="#{value}") end)
  end

  defp number(value), do: value |> Kernel.*(1.0) |> Float.round(4) |> to_string()

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
