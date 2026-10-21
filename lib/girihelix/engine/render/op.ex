defmodule Girihelix.Engine.Render.Op do
  @moduledoc """
  The draw-op vocabulary: the five things a drawing can ask a renderer to draw.

  An op is a plain tagged tuple, not a struct, so an exhibit, a test and a golden
  file spell it the same way and no constructor stands between them.

  **Two coordinate spaces.** Every point is in **map space**, y-up, exactly as the
  geometry core produces it. Measurements in SVG units are not: a `:point`'s
  radius is the tuple's third element, and a `:label`'s font size is carried in
  `opts`. Both must keep their screen size as the viewport changes, so the
  serializer must never project them. This module does not interpret `opts` at
  all; `known?/1` only requires an options list to be present, and the serializer
  decides which keys each op accepts.

  **Shallow validation.** `known?/1` checks the outer tuple — its tag, arity,
  polygon mode and label text — not the coordinates nested inside it. Coordinates
  are the caller's contract, and `points/1` reads them back without a decode step.
  """

  @type point :: {number(), number()}
  @type opts :: keyword()

  @type t ::
          {:line, point(), point(), opts()}
          | {:polygon, [point()], :fill | :stroke, opts()}
          | {:point, point(), number(), opts()}
          | {:label, point(), String.t(), opts()}
          | {:guide, point(), point(), opts()}

  @doc """
  Whether `term` has the shape of one of the five known draw ops.

  `:polygon` must carry `:fill` or `:stroke`, a label must carry a string, and
  every op must carry an options list. Anything else — an unknown tag, a wrong
  arity, a malformed discriminator — is `false`, so a renderer can reject foreign
  input with one predicate.
  """
  @spec known?(term()) :: boolean()
  def known?({:line, _from, _to, opts}) when is_list(opts), do: true
  def known?({:guide, _from, _to, opts}) when is_list(opts), do: true
  def known?({:point, _at, radius, opts}) when is_number(radius) and is_list(opts), do: true
  def known?({:label, _at, text, opts}) when is_binary(text) and is_list(opts), do: true

  def known?({:polygon, vertices, mode, opts}) when is_list(vertices) and mode in [:fill, :stroke] and is_list(opts) do
    true
  end

  def known?(_term), do: false

  @doc """
  Every positional point the op draws at, in order.

  A `:point` and a `:label` contribute one point, a `:line` and a `:guide`
  contribute their two ends, and a `:polygon` contributes all its vertices. An
  unknown op raises `ArgumentError`, because `known?/1` has already had the chance
  to reject it.
  """
  @spec points(t()) :: [point()]
  def points({:line, from, to, _opts}), do: [from, to]
  def points({:guide, from, to, _opts}), do: [from, to]
  def points({:point, at, _radius, _opts}), do: [at]
  def points({:label, at, _text, _opts}), do: [at]
  def points({:polygon, vertices, _mode, _opts}), do: vertices

  def points(_op), do: raise(ArgumentError, "unknown draw op")
end
