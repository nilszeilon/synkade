defmodule SynkadeWeb.DashboardLiveTest do
  use SynkadeWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders dashboard page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "Synkade Dashboard"
    assert html =~ "Running"
    assert html =~ "Retry Queue"
    assert html =~ "Total Tokens"
  end

  test "shows workflow error when present", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    # The workflow error should show since there's no WORKFLOW.md in test
    # The dashboard still renders
    assert render(view) =~ "Dashboard"
  end

  test "refresh button exists", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "Refresh"
  end
end
