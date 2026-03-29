defmodule SynkadeWeb.SettingsLiveTest do
  use SynkadeWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders settings page with tabs", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings")
    assert html =~ "Settings"
    assert html =~ "GitHub"
    assert html =~ "Agents"
    assert html =~ "Execution"
  end

  test "shows PAT field by default", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings")
    assert html =~ "Personal Access Token"
  end

  test "switches to agents tab and shows integrations", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")
    html = view |> element(~s{button[phx-value-tab="agents"]}) |> render_click()
    assert html =~ "Integrations"
    assert html =~ "Claude Code"
  end

  test "agents tab shows configured ephemeral agent", %{conn: conn} do
    # The onboarding fixture already creates a claude agent
    {:ok, view, _html} = live(conn, "/settings")
    html = view |> element(~s{button[phx-value-tab="agents"]}) |> render_click()
    assert html =~ "Claude Code"
    assert html =~ "Connected"
  end

  test "agents tab shows pull agents section", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")
    html = view |> element(~s{button[phx-value-tab="agents"]}) |> render_click()
    assert html =~ "Pull Agents"
    assert html =~ "New Pull Agent"
  end

  test "validates on change", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")

    html =
      view
      |> form(~s{form[phx-submit="save"]}, setting: %{github_pat: ""})
      |> render_change()

    assert html =~ "can&#39;t be blank"
  end

  test "saves valid settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")

    view
    |> form(~s{form[phx-submit="save"]},
      setting: %{
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
      |> form(~s{form[phx-submit="save"]}, setting: %{github_pat: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
  end

  test "switches to execution tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")
    html = view |> element(~s{button[phx-value-tab="execution"]}) |> render_click()
    assert html =~ "Execution Backend"
  end
end
