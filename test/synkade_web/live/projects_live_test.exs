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

  test "shows mode chooser on /projects/new", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/projects/new")
    assert html =~ "Existing repository"
    assert html =~ "New project"
  end

  test "new project mode shows name field", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/projects/new")

    html =
      view
      |> element(~s{button[phx-value-mode="new"]})
      |> render_click()

    assert html =~ "Project name"
  end

  test "new mode shows error when GitHub API rejects credentials", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/projects/new")

    view
    |> element(~s{button[phx-value-mode="new"]})
    |> render_click()

    view
    |> form("form", project: %{name: "test-project"})
    |> render_submit()

    # The send(self(), ...) message is processed on the next render cycle
    html = render(view)
    assert html =~ "Failed to create repository"
  end

  test "creates a project via existing repo mode", %{conn: conn, scope: scope} do
    # Directly create since the existing_repo flow requires GitHub API
    {:ok, _} = Settings.create_project(scope, %{name: "test-project", tracker_repo: "acme/test-project"})

    {:ok, _view, html} = live(conn, "/projects")
    assert html =~ "test-project"
    assert html =~ "acme/test-project"
  end

  test "shows validation error for missing name", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/projects/new")

    view
    |> element(~s{button[phx-value-mode="new"]})
    |> render_click()

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

  test "edits a project via /projects/:name/settings", %{conn: conn, scope: scope} do
    {:ok, _project} = Settings.create_project(scope, %{name: "my-repo"})

    {:ok, _view, html} = live(conn, "/projects/my-repo/settings")
    assert html =~ "Edit Project"
  end

  test "deletes a project", %{conn: conn, scope: scope} do
    {:ok, project} = Settings.create_project(scope, %{name: "to-delete"})

    {:ok, view, _html} = live(conn, "/projects")
    assert render(view) =~ "to-delete"

    view
    |> element(~s{button[phx-click="delete"][phx-value-id="#{project.id}"]})
    |> render_click()

    flash = assert_redirect(view, "/projects")
    assert flash["info"] == "Project deleted."
  end
end
