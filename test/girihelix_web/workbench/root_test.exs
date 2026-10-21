defmodule GirihelixWeb.Workbench.RootTest do
  use GirihelixWeb.ConnCase

  test "GET / renders the workbench index", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Workbench"
  end
end
