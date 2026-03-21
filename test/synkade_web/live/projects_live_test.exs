defmodule SynkadeWeb.ProjectsLiveTest do
  use SynkadeWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Synkade.Settings

  setup :register_and_log_in_user

  test "renders projects page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/projects")
    assert html =~ "Projects"
    assert html =~ "New Project"
  end

  test "shows empty state when no projects", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/projects")
    assert html =~ "No projects configured yet"
  end

  test "opens new project form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/projects")
    html = view |> element("button", "New Project") |> render_click()
    assert html =~ "New Project"
    assert html =~ "Name"
  end

  test "creates a project", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/projects")
    view |> element("button", "New Project") |> render_click()

    view
    |> form("form", project: %{name: "test-project", tracker_repo: "acme/api"})
    |> render_submit()

    html = render(view)
    assert html =~ "Project saved"
    assert html =~ "test-project"
  end

  test "shows validation error for missing name", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/projects")
    view |> element("button", "New Project") |> render_click()

    html =
      view
      |> form("form", project: %{name: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
  end

  test "lists existing projects", %{conn: conn, scope: scope} do
    {:ok, _} = Settings.create_project(scope, %{name: "my-repo", tracker_repo: "acme/repo"})

    {:ok, _view, html} = live(conn, "/projects")
    assert html =~ "my-repo"
    assert html =~ "acme/repo"
  end

  test "deletes a project", %{conn: conn, scope: scope} do
    {:ok, project} = Settings.create_project(scope, %{name: "to-delete"})

    {:ok, view, _html} = live(conn, "/projects")
    assert render(view) =~ "to-delete"

    view
    |> element(~s{button[phx-click="delete"][phx-value-id="#{project.id}"]})
    |> render_click()

    html = render(view)
    assert html =~ "Project deleted"
    refute html =~ "to-delete"
  end
end
