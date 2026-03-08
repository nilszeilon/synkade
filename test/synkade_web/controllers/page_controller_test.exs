defmodule SynkadeWeb.PageControllerTest do
  use SynkadeWeb.ConnCase

  test "GET / renders dashboard", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Synkade Dashboard"
  end
end
