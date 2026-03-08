defmodule SynkadeWeb.GitHub.OAuthControllerTest do
  use SynkadeWeb.ConnCase, async: true

  test "redirects to dashboard with flash", %{conn: conn} do
    conn = get(conn, "/github/callback")
    assert redirected_to(conn) == "/"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "GitHub App installed"
  end
end
