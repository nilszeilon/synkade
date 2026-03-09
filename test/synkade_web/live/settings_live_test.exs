defmodule SynkadeWeb.SettingsLiveTest do
  use SynkadeWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders settings page with tabs", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings")
    assert html =~ "Settings"
    assert html =~ "GitHub"
    assert html =~ "Agents"
    assert html =~ "Execution"
  end

  test "shows PAT fields by default", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings")
    assert html =~ "Personal Access Token"
  end

  test "switches to agents tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")
    html = view |> element(~s{button[phx-value-tab="agents"]}) |> render_click()
    assert html =~ "API Key"
    assert html =~ "Max Turns"
  end

  test "validates on change", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")

    html =
      view
      |> form("form", setting: %{github_auth_mode: "pat", github_pat: ""})
      |> render_change()

    assert html =~ "is required for PAT auth mode"
  end

  test "saves valid settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")

    view
    |> form("form",
      setting: %{
        github_auth_mode: "pat",
        github_pat: "ghp_test123"
      }
    )
    |> render_submit()

    assert render(view) =~ "Settings saved"
  end

  test "shows validation errors on submit", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")

    html =
      view
      |> form("form", setting: %{github_auth_mode: "pat", github_pat: ""})
      |> render_submit()

    assert html =~ "is required for PAT auth mode"
  end

  test "shows OAuth Token field when auth mode is oauth", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")

    # Switch to agents tab
    view |> element(~s{button[phx-value-tab="agents"]}) |> render_click()

    # Change auth mode to oauth
    html =
      view
      |> form("form", setting: %{agent_auth_mode: "oauth"})
      |> render_change()

    assert html =~ "OAuth Token"
    refute html =~ ~s(placeholder="sk-ant-...")
  end

  test "shows API Key field when auth mode is api_key", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")

    # Switch to agents tab
    html = view |> element(~s{button[phx-value-tab="agents"]}) |> render_click()

    # Default is api_key mode
    assert html =~ ~s(placeholder="sk-ant-...")
  end

  test "switches to execution tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")
    html = view |> element(~s{button[phx-value-tab="execution"]}) |> render_click()
    assert html =~ "Execution Backend"
  end
end
