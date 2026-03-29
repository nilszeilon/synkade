defmodule SynkadeWeb.Api.AgentHeartbeatControllerTest do
  use SynkadeWeb.ConnCase

  import Synkade.AccountsFixtures

  alias Synkade.Settings
  alias Synkade.Issues

  setup do
    scope = user_scope_fixture()
    {:ok, agent} = Settings.create_agent(scope, %{kind: "claude"})
    {:ok, token} = Settings.generate_agent_token(agent)

    {:ok, project} =
      Settings.create_project(scope, %{name: "heartbeat-test-project", default_agent_id: agent.id})

    {:ok, issue} =
      Issues.create_issue(%{
        body: "# Heartbeat test issue\n\nTesting heartbeat",
        project_id: project.id
      })

    %{agent: agent, token: token, project: project, issue: issue, scope: scope}
  end

  defp auth_conn(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "POST /api/v1/agent/heartbeat" do
    test "returns 200 for valid heartbeat", %{conn: conn, token: token, issue: issue} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/heartbeat", %{
          issue_id: issue.id,
          status: "working",
          message: "Implementing feature"
        })

      assert json_response(conn, 200)["ok"] == true
    end

    test "accepts error status", %{conn: conn, token: token, issue: issue} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/heartbeat", %{
          issue_id: issue.id,
          status: "error",
          message: "Build failed"
        })

      assert json_response(conn, 200)["ok"] == true
    end

    test "accepts blocked status", %{conn: conn, token: token, issue: issue} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/heartbeat", %{
          issue_id: issue.id,
          status: "blocked"
        })

      assert json_response(conn, 200)["ok"] == true
    end

    test "returns 400 for invalid status", %{conn: conn, token: token, issue: issue} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/heartbeat", %{
          issue_id: issue.id,
          status: "invalid"
        })

      assert json_response(conn, 400)["error"] =~ "status must be one of"
    end

    test "returns 400 without required fields", %{conn: conn, token: token} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/heartbeat", %{})

      assert json_response(conn, 400)["error"] == "issue_id and status are required"
    end

    test "returns 404 for nonexistent issue", %{conn: conn, token: token} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/heartbeat", %{
          issue_id: Ecto.UUID.generate(),
          status: "working"
        })

      assert json_response(conn, 404)["error"] == "not found"
    end

    test "returns 403 for unauthorized project", %{conn: conn, token: token, scope: scope} do
      {:ok, other_project} = Settings.create_project(scope, %{name: "other-heartbeat-project"})

      {:ok, other_issue} =
        Issues.create_issue(%{
          body: "# Other issue",
          project_id: other_project.id
        })

      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/heartbeat", %{
          issue_id: other_issue.id,
          status: "working"
        })

      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "returns 401 without token", %{conn: conn, issue: issue} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/heartbeat", %{
          issue_id: issue.id,
          status: "working"
        })

      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end
end
