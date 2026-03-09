defmodule Synkade.Tracker.GitHubTest do
  use ExUnit.Case, async: true

  alias Synkade.Tracker.GitHub
  alias Synkade.Tracker.Issue

  defp make_config(plug_name) do
    %{
      "tracker" => %{
        "kind" => "github",
        "repo" => "acme/api",
        "api_key" => "test_token"
      },
      "__req_options__" => [plug: {Req.Test, plug_name}]
    }
  end

  describe "fetch_candidate_issues" do
    test "normalizes GitHub issues correctly" do
      name = :github_normalize
      config = make_config(name)

      Req.Test.stub(name, fn conn ->
        Req.Test.json(conn, [
          %{
            "number" => 42,
            "title" => "Fix login",
            "body" => "Login is broken.\n\nBlocked by #10",
            "state" => "open",
            "html_url" => "https://github.com/acme/api/issues/42",
            "labels" => [%{"name" => "Bug"}, %{"name" => "Priority:1"}],
            "created_at" => "2024-01-15T10:00:00Z",
            "updated_at" => "2024-01-16T12:00:00Z"
          }
        ])
      end)

      assert {:ok, [issue]} = GitHub.fetch_candidate_issues(config, "api")
      assert %Issue{} = issue
      assert issue.id == "42"
      assert issue.identifier == "acme/api#42"
      assert issue.title == "Fix login"
      assert issue.state == "open"
      assert issue.labels == ["bug", "priority:1"]
      assert issue.priority == 1
      assert issue.blocked_by == [%{id: "10", identifier: "#10", state: nil}]
      assert issue.url == "https://github.com/acme/api/issues/42"
      assert issue.project_name == "api"
    end

    test "filters out pull requests" do
      name = :github_pr_filter
      config = make_config(name)

      Req.Test.stub(name, fn conn ->
        Req.Test.json(conn, [
          %{
            "number" => 1,
            "title" => "Issue",
            "body" => nil,
            "state" => "open",
            "html_url" => "https://github.com/acme/api/issues/1",
            "labels" => [],
            "created_at" => "2024-01-15T10:00:00Z",
            "updated_at" => "2024-01-15T10:00:00Z"
          },
          %{
            "number" => 2,
            "title" => "PR",
            "body" => nil,
            "state" => "open",
            "pull_request" => %{"url" => "https://api.github.com/repos/acme/api/pulls/2"},
            "html_url" => "https://github.com/acme/api/pulls/2",
            "labels" => [],
            "created_at" => "2024-01-15T10:00:00Z",
            "updated_at" => "2024-01-15T10:00:00Z"
          }
        ])
      end)

      assert {:ok, issues} = GitHub.fetch_candidate_issues(config, "api")
      assert length(issues) == 1
      assert hd(issues).title == "Issue"
    end

    test "handles label lowercase normalization" do
      name = :github_labels
      config = make_config(name)

      Req.Test.stub(name, fn conn ->
        Req.Test.json(conn, [
          %{
            "number" => 1,
            "title" => "Test",
            "body" => nil,
            "state" => "open",
            "html_url" => "https://github.com/acme/api/issues/1",
            "labels" => [%{"name" => "BUG"}, %{"name" => "Enhancement"}],
            "created_at" => "2024-01-15T10:00:00Z",
            "updated_at" => "2024-01-15T10:00:00Z"
          }
        ])
      end)

      assert {:ok, [issue]} = GitHub.fetch_candidate_issues(config, "api")
      assert issue.labels == ["bug", "enhancement"]
    end

    test "handles API errors" do
      name = :github_error
      config = make_config(name)

      Req.Test.stub(name, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(401, Jason.encode!(%{"message" => "Bad credentials"}))
      end)

      assert {:error, _reason} = GitHub.fetch_candidate_issues(config, "api")
    end

    test "parses multiple blockers from body" do
      name = :github_blockers
      config = make_config(name)

      Req.Test.stub(name, fn conn ->
        Req.Test.json(conn, [
          %{
            "number" => 5,
            "title" => "Blocked issue",
            "body" => "Blocked by #1 and also depends on #2",
            "state" => "open",
            "html_url" => "https://github.com/acme/api/issues/5",
            "labels" => [],
            "created_at" => "2024-01-15T10:00:00Z",
            "updated_at" => "2024-01-15T10:00:00Z"
          }
        ])
      end)

      assert {:ok, [issue]} = GitHub.fetch_candidate_issues(config, "api")
      assert length(issue.blocked_by) == 2
    end
  end

  describe "fetch_pr_status" do
    test "returns merged status" do
      name = :github_pr_merged
      config = make_config(name)

      Req.Test.stub(name, fn conn ->
        Req.Test.json(conn, %{"state" => "closed", "merged" => true})
      end)

      assert {:ok, %{state: "closed", merged: true}} =
               GitHub.fetch_pr_status(config, "api", "10")
    end

    test "returns open status" do
      name = :github_pr_open
      config = make_config(name)

      Req.Test.stub(name, fn conn ->
        Req.Test.json(conn, %{"state" => "open", "merged" => false})
      end)

      assert {:ok, %{state: "open", merged: false}} =
               GitHub.fetch_pr_status(config, "api", "10")
    end

    test "returns error for not found" do
      name = :github_pr_404
      config = make_config(name)

      Req.Test.stub(name, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{"message" => "Not Found"}))
      end)

      assert {:error, :not_found} = GitHub.fetch_pr_status(config, "api", "999")
    end

    test "handles API error" do
      name = :github_pr_error
      config = make_config(name)

      Req.Test.stub(name, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, Jason.encode!(%{"message" => "Server Error"}))
      end)

      assert {:error, _} = GitHub.fetch_pr_status(config, "api", "10")
    end
  end

  describe "fetch_issue_states_by_ids" do
    test "fetches individual issue states" do
      name = :github_states
      config = make_config(name)

      Req.Test.stub(name, fn conn ->
        number = conn.path_info |> List.last()

        body =
          case number do
            "1" -> %{"state" => "open"}
            "2" -> %{"state" => "closed"}
          end

        Req.Test.json(conn, body)
      end)

      assert {:ok, states} = GitHub.fetch_issue_states_by_ids(config, "api", ["1", "2"])
      assert states["1"] == "open"
      assert states["2"] == "closed"
    end
  end
end
