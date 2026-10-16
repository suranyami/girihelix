defmodule GirihelixWeb.PageController do
  use GirihelixWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
