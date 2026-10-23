defmodule GirihelixWeb.Workbench.Exhibit do
  @moduledoc """
  The contract every workbench exhibit implements.

  An exhibit is a pure description of one algorithm: its identity, its declared
  parameters, the step sequence that computes it, and how a built frame is drawn.
  The workbench supplies everything else — controls, URL state, transport, source
  highlighting — so adding an exhibit is one module plus one line in
  `GirihelixWeb.Workbench.Registry`, never a change to the framework.

  `initial/1` and `steps/1` receive the typed parameter map, and `draw/2` receives
  the frame together with that same map, so an exhibit never reads state from
  anywhere else. `reproduce/1` returns the plain call a reader can paste into
  `iex`, which is what keeps the debugger honest about the engine beneath it.

  `viewport/1` is optional. Omitting it means `:fit`: the canvas frames the
  current frame's bounds. An exhibit pins a viewport only when auto-fitting would
  make a figure visibly jitter as it is built.
  """

  alias Girihelix.Engine.Render.Op
  alias Girihelix.Engine.Render.Viewport
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Param

  @typedoc """
  What an exhibit draws for one frame.

  `:canvas` is a list of draw ops, `:panel` is a table of label/value rows, and
  `:both` carries a picture and its numbers. A non-geometric exhibit uses
  `:panel`; a geometric one uses either of the others.
  """
  @type drawing ::
          {:canvas, [Op.t()]}
          | {:panel, [{String.t(), String.t()}]}
          | {:both, [Op.t()], [{String.t(), String.t()}]}

  @doc "The URL segment and registry key; unique across all exhibits."
  @callback slug() :: String.t()

  @doc "The heading shown on the exhibit page."
  @callback title() :: String.t()

  @doc "The tag-line under the page header's title: the old title's text after the em-dash."
  @callback byline() :: String.t()

  @doc "One sentence describing what the exhibit shows."
  @callback summary() :: String.t()

  @doc "The index grouping: `:geometry`, `:figures`, `:tilings` or `:styles`."
  @callback category() :: atom()

  @doc "The exhibit's declarative parameters, in control order."
  @callback params() :: [Param.t()]

  @doc "The state frame zero starts from, at typed parameter `params`."
  @callback initial(params :: map()) :: term()

  @doc "The labelled computation, as steps over the initial state."
  @callback steps(params :: map()) :: [Steps.Step.t()]

  @doc "The picture, the panel rows, or both, for `frame`."
  @callback draw(frame :: Steps.Frame.t(), params :: map()) :: drawing()

  @doc "The plain engine call that reproduces this exhibit's result."
  @callback reproduce(params :: map()) :: String.t()

  @doc "`:fit` (the default) or a pinned viewport."
  @callback viewport(params :: map()) :: :fit | Viewport.t()

  @optional_callbacks viewport: 1
end
