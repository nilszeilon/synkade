defmodule SynkadeWeb.PageControllerTest do
  use SynkadeWeb.ConnCase

  test "GET / redirects to login when not authenticated", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "GET / renders dashboard", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Overview"
    end
  end
end
