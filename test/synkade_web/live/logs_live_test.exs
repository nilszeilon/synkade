defmodule SynkadeWeb.LogsLiveTest do
  use SynkadeWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders logs page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/logs")
    assert html =~ "System Logs"
    assert html =~ "entries"
  end

  test "level filter buttons are visible", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/logs")
    assert html =~ "All"
    assert html =~ "Info"
    assert html =~ "Warning"
    assert html =~ "Error"
  end

  test "pause toggle works", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/logs")
    html = view |> element(~s{button[phx-click="toggle_pause"]}) |> render_click()
    assert html =~ "Resume"

    html = view |> element(~s{button[phx-click="toggle_pause"]}) |> render_click()
    assert html =~ "Pause"
  end

  test "clear empties entries", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/logs")
    html = view |> element(~s{button[phx-click="clear"]}) |> render_click()
    assert html =~ "No log entries"
  end

  test "level filter changes active button", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/logs")
    html = view |> element(~s{button[phx-value-level="error"]}) |> render_click()
    assert html =~ "btn-active"
  end

  test "search input is present", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/logs")
    assert html =~ "Filter logs..."
  end
end
