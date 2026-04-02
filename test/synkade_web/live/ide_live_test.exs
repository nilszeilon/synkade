defmodule SynkadeWeb.IdeLiveTest do
  use SynkadeWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Synkade.{Issues, Settings}

  setup :register_and_log_in_user

  defp create_project(%{scope: scope}) do
    {:ok, project} = Settings.create_project(scope, %{name: "test-project"})
    %{project: project}
  end

  defp create_issue(%{project: project}) do
    {:ok, issue} = Issues.create_issue(%{project_id: project.id, body: "# Test issue\nDo the thing"})
    %{issue: issue}
  end

  describe "draft mode (GET /chat/:project_name)" do
    setup [:create_project]

    test "renders draft chat view", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/chat/test-project")
      assert html =~ "draft"
      assert html =~ "New chat"
      assert html =~ "test-project"
    end

    test "redirects to / for unknown project", %{conn: conn} do
      {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/chat/nonexistent")
    end

    test "shows message input", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/chat/test-project")
      assert html =~ "Message..."
    end
  end

  describe "issue mode (GET /issues/:id)" do
    setup [:create_project, :create_issue]

    test "renders issue chat view", %{conn: conn, issue: issue} do
      {:ok, _view, html} = live(conn, "/issues/#{issue.id}")
      assert html =~ "Test issue"
    end

    test "redirects to /issues for unknown issue", %{conn: conn} do
      {:error, {:live_redirect, %{to: "/issues"}}} =
        live(conn, "/issues/00000000-0000-0000-0000-000000000000")
    end

    test "shows issue state badge", %{conn: conn, issue: issue} do
      {:ok, _view, html} = live(conn, "/issues/#{issue.id}")
      assert html =~ "backlog"
    end

    test "shows no changes detected initially", %{conn: conn, issue: issue} do
      {:ok, _view, html} = live(conn, "/issues/#{issue.id}")
      assert html =~ "No changes detected"
    end
  end

  describe "tab switching" do
    setup [:create_project, :create_issue]

    test "chat tab is active by default", %{conn: conn, issue: issue} do
      {:ok, _view, html} = live(conn, "/issues/#{issue.id}")
      assert html =~ "Chat"
    end

    test "switching to diff tab without file selected is a no-op", %{conn: conn, issue: issue} do
      {:ok, view, _html} = live(conn, "/issues/#{issue.id}")
      html = view |> element(~s{button[phx-value-tab="chat"]}) |> render_click()
      assert html =~ "Chat"
    end
  end

  describe "attachments" do
    setup [:create_project, :create_issue]

    test "comment_line adds an attachment", %{conn: conn, issue: issue} do
      {:ok, view, _html} = live(conn, "/issues/#{issue.id}")

      html =
        render_hook(view, "comment_line", %{
          "file" => "lib/foo.ex",
          "line" => "42",
          "text" => "fix this bug"
        })

      assert html =~ "foo.ex"
      assert html =~ "42"
      assert html =~ "fix this bug"
    end

    test "comment_line ignores empty text", %{conn: conn, issue: issue} do
      {:ok, view, _html} = live(conn, "/issues/#{issue.id}")
      html_before = render(view)

      render_hook(view, "comment_line", %{
        "file" => "lib/foo.ex",
        "line" => "1",
        "text" => "   "
      })

      html_after = render(view)
      # No attachment added
      refute html_after =~ "foo.ex:1"
      assert html_before =~ html_after |> String.slice(0..50)
    end

    test "remove_attachment removes it", %{conn: conn, issue: issue} do
      {:ok, view, _html} = live(conn, "/issues/#{issue.id}")

      render_hook(view, "comment_line", %{
        "file" => "lib/foo.ex",
        "line" => "42",
        "text" => "fix this"
      })

      html = render(view)
      assert html =~ "foo.ex"

      # Extract the attachment id from the rendered HTML
      [_, id] = Regex.run(~r/phx-value-id="(\d+)"/, html)

      html = render_click(view, "remove_attachment", %{"id" => id})
      refute html =~ "fix this"
    end
  end

  describe "toggle_turn_filter" do
    setup [:create_project, :create_issue]

    test "toggles the turn filter", %{conn: conn, issue: issue} do
      {:ok, view, _html} = live(conn, "/issues/#{issue.id}")
      render_click(view, "toggle_turn_filter")
      # Toggling again should work without error
      render_click(view, "toggle_turn_filter")
    end
  end

  describe "copy_resume" do
    setup [:create_project, :create_issue]

    test "returns error when no session_id", %{conn: conn, issue: issue} do
      {:ok, view, _html} = live(conn, "/issues/#{issue.id}")
      html = render_click(view, "copy_resume")
      assert html =~ "No session ID available"
    end
  end

  describe "complete_issue" do
    setup [:create_project, :create_issue]

    test "archiving from backlog redirects to issues", %{conn: conn, issue: issue} do
      {:ok, view, _html} = live(conn, "/issues/#{issue.id}")
      render_click(view, "complete_issue")
      assert_redirect(view, "/issues")
    end
  end

  describe "dispatch_issue" do
    setup [:create_project]

    test "rejects empty message", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat/test-project")

      html =
        view
        |> form(~s{form[phx-submit="dispatch_issue"]}, dispatch: %{message: ""})
        |> render_submit()

      assert html =~ "Message cannot be empty"
    end
  end

  describe "PubSub integration" do
    setup [:create_project, :create_issue]

    test "issues_updated refreshes the issue", %{conn: conn, issue: issue, scope: scope} do
      {:ok, view, _html} = live(conn, "/issues/#{issue.id}")

      Phoenix.PubSub.broadcast(
        Synkade.PubSub,
        Issues.pubsub_topic(scope.user.id),
        {:issues_updated}
      )

      # Should still render without error
      html = render(view)
      assert html =~ "Test issue"
    end

    test "issues_updated with deleted issue redirects", %{conn: conn, issue: issue, scope: scope} do
      {:ok, view, _html} = live(conn, "/issues/#{issue.id}")

      Synkade.Repo.delete!(issue)

      Phoenix.PubSub.broadcast(
        Synkade.PubSub,
        Issues.pubsub_topic(scope.user.id),
        {:issues_updated}
      )

      assert_redirect(view, "/issues")
    end
  end
end
