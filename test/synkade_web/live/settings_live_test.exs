defmodule SynkadeWeb.SettingsLiveTest do
  use SynkadeWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Synkade.Settings

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

  test "switches to agents tab and shows agent list", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")
    html = view |> element(~s{button[phx-value-tab="agents"]}) |> render_click()
    assert html =~ "New Agent"
    assert html =~ "No agents configured yet"
  end

  test "agents tab shows existing agents", %{conn: conn, scope: scope} do
    {:ok, _} = Settings.create_agent(scope, %{name: "test-agent", kind: "claude", model: "sonnet"})

    {:ok, view, _html} = live(conn, "/settings")
    html = view |> element(~s{button[phx-value-tab="agents"]}) |> render_click()
    assert html =~ "test-agent"
    assert html =~ "Claude Code"
    assert html =~ "sonnet"
  end

  test "opens new agent form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")
    view |> element(~s{button[phx-value-tab="agents"]}) |> render_click()
    html = view |> element(~s{button[phx-click="new_agent"]}) |> render_click()
    assert html =~ "New Agent"
    assert html =~ "Name"
    assert html =~ "Kind"
  end

  test "creates an agent", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")
    view |> element(~s{button[phx-value-tab="agents"]}) |> render_click()
    view |> element(~s{button[phx-click="new_agent"]}) |> render_click()

    view
    |> form(~s{form[phx-submit="save_agent"]}, agent: %{name: "new-agent", kind: "claude"})
    |> render_submit()

    html = render(view)
    assert html =~ "Agent saved"
    assert html =~ "new-agent"
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
