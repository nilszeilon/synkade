defmodule SynkadeWeb.PageControllerTest do
  use SynkadeWeb.ConnCase

  test "GET / redirects to setup when no users exist", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/setup"
  end

  test "GET / redirects to login when not authenticated but setup is complete", %{conn: conn} do
    Synkade.AccountsFixtures.user_fixture()
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
