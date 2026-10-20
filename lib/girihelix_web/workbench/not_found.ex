defmodule GirihelixWeb.Workbench.NotFound do
  @moduledoc """
  The error raised when a workbench URL names an exhibit that does not exist.

  An unknown slug is a missing page, not a broken application, so the exception
  carries `404` as its Plug status and offers no recovery actions. Raising it
  from the exhibit LiveView's `handle_params/3` is what turns `/workbench/nope`
  into an ordinary not-found response.
  """

  defexception plug_status: 404, message: "unknown workbench exhibit"

  @type t :: %__MODULE__{}
end

defimpl Plug.Exception, for: GirihelixWeb.Workbench.NotFound do
  @spec status(GirihelixWeb.Workbench.NotFound.t()) :: 404
  def status(_exception), do: 404

  @spec actions(GirihelixWeb.Workbench.NotFound.t()) :: []
  def actions(_exception), do: []
end
