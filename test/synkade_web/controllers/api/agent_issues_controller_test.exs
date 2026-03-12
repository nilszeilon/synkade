defmodule SynkadeWeb.Api.AgentIssuesControllerTest do
  use SynkadeWeb.ConnCase, async: true

  alias Synkade.Settings
  alias Synkade.Issues

  setup do
    {:ok, agent} = Settings.create_agent(%{name: "api-test-agent"})
    {:ok, token} = Settings.generate_agent_token(agent)

    {:ok, project} =
      Settings.create_project(%{name: "api-test-project", default_agent_id: agent.id})

    {:ok, issue} =
      Issues.create_issue(%{
        body: "# Test issue\n\nA test issue",
        project_id: project.id
      })

    %{agent: agent, token: token, project: project, issue: issue}
  end

  defp auth_conn(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  # --- Index ---

  describe "GET /api/v1/agent/issues" do
    test "lists issues for project", %{conn: conn, token: token, project: project, issue: issue} do
      conn =
        conn
        |> auth_conn(token)
        |> get(~p"/api/v1/agent/issues?project_id=#{project.id}")

      assert %{"data" => issues} = json_response(conn, 200)
      assert length(issues) == 1
      assert hd(issues)["id"] == issue.id
    end

    test "returns 400 without project_id", %{conn: conn, token: token} do
      conn =
        conn
        |> auth_conn(token)
        |> get(~p"/api/v1/agent/issues")

      assert json_response(conn, 400)["error"] == "project_id is required"
    end

    test "returns 403 for unauthorized project", %{conn: conn, token: token} do
      {:ok, other_project} = Settings.create_project(%{name: "other-project"})

      conn =
        conn
        |> auth_conn(token)
        |> get(~p"/api/v1/agent/issues?project_id=#{other_project.id}")

      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "returns 401 without token", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/v1/agent/issues?project_id=#{project.id}")
      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end

  # --- Create ---

  describe "POST /api/v1/agent/issues" do
    test "creates an issue with body", %{conn: conn, token: token, project: project} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/issues", %{
          project_id: project.id,
          body: "# New from API\n\nCreated via API"
        })

      assert %{"data" => issue} = json_response(conn, 201)
      assert issue["title"] == "New from API"
      assert issue["body"] == "# New from API\n\nCreated via API"
      assert issue["state"] == "backlog"
    end

    test "creates issue with backwards-compat title+description", %{
      conn: conn,
      token: token,
      project: project
    } do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/issues", %{
          project_id: project.id,
          title: "Legacy title",
          description: "Legacy description"
        })

      assert %{"data" => issue} = json_response(conn, 201)
      assert issue["title"] == "Legacy title"
      assert issue["body"] == "# Legacy title\n\nLegacy description"
    end

    test "creates a child issue", %{conn: conn, token: token, project: project, issue: parent} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/issues", %{
          project_id: project.id,
          body: "# Child issue",
          parent_id: parent.id
        })

      assert %{"data" => child} = json_response(conn, 201)
      assert child["parent_id"] == parent.id
    end

    test "creates issue with only project_id", %{conn: conn, token: token, project: project} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/issues", %{project_id: project.id})

      assert %{"data" => issue} = json_response(conn, 201)
      assert issue["title"] == "Unnamed"
    end

    test "returns 400 without project_id", %{conn: conn, token: token} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/issues", %{})

      assert json_response(conn, 400)["error"] == "project_id is required"
    end

    test "returns 403 for unauthorized project", %{conn: conn, token: token} do
      {:ok, other_project} = Settings.create_project(%{name: "other-create-project"})

      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/issues", %{
          project_id: other_project.id,
          body: "# Should fail"
        })

      assert json_response(conn, 403)["error"] == "forbidden"
    end
  end

  # --- Show ---

  describe "GET /api/v1/agent/issues/:id" do
    test "returns issue with children", %{
      conn: conn,
      token: token,
      project: project,
      issue: issue
    } do
      {:ok, _child} =
        Issues.create_issue(%{
          body: "# Child",
          project_id: project.id,
          parent_id: issue.id
        })

      conn =
        conn
        |> auth_conn(token)
        |> get(~p"/api/v1/agent/issues/#{issue.id}")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == issue.id
      assert length(data["children"]) == 1
    end

    test "returns 404 for nonexistent issue", %{conn: conn, token: token} do
      conn =
        conn
        |> auth_conn(token)
        |> get(~p"/api/v1/agent/issues/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)["error"] == "not found"
    end
  end

  # --- Update ---

  describe "PATCH /api/v1/agent/issues/:id" do
    test "updates body", %{conn: conn, token: token, issue: issue} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/v1/agent/issues/#{issue.id}", %{
          body: "# Updated title\n\nUpdated desc"
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["title"] == "Updated title"
      assert data["body"] == "# Updated title\n\nUpdated desc"
    end

    test "updates with backwards-compat title+description", %{
      conn: conn,
      token: token,
      issue: issue
    } do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/v1/agent/issues/#{issue.id}", %{
          title: "Legacy update",
          description: "Legacy desc"
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["title"] == "Legacy update"
      assert data["body"] == "# Legacy update\n\nLegacy desc"
    end

    test "transitions state", %{conn: conn, token: token, issue: issue} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/v1/agent/issues/#{issue.id}", %{state: "queued"})

      assert %{"data" => data} = json_response(conn, 200)
      assert data["state"] == "queued"
    end

    test "rejects invalid state transition", %{conn: conn, token: token, issue: issue} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/v1/agent/issues/#{issue.id}", %{state: "done"})

      assert json_response(conn, 422)["error"] == "invalid state transition"
    end

    test "returns 404 for nonexistent issue", %{conn: conn, token: token} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/v1/agent/issues/#{Ecto.UUID.generate()}", %{body: "# x"})

      assert json_response(conn, 404)["error"] == "not found"
    end
  end

  # --- Create Children ---

  describe "POST /api/v1/agent/issues/:id/children" do
    test "creates multiple children with body", %{conn: conn, token: token, issue: parent} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/issues/#{parent.id}/children", %{
          children: [
            %{body: "# Child A\n\nFirst"},
            %{body: "# Child B\n\nSecond"}
          ]
        })

      assert %{"data" => children} = json_response(conn, 201)
      assert length(children) == 2
    end

    test "creates children with backwards-compat title+description", %{
      conn: conn,
      token: token,
      issue: parent
    } do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/issues/#{parent.id}/children", %{
          children: [
            %{title: "Legacy A", description: "First"},
            %{title: "Legacy B", description: "Second"}
          ]
        })

      assert %{"data" => children} = json_response(conn, 201)
      assert length(children) == 2
    end

    test "returns 404 for nonexistent parent", %{conn: conn, token: token} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/agent/issues/#{Ecto.UUID.generate()}/children", %{
          children: [%{body: "# x"}]
        })

      assert json_response(conn, 404)["error"] == "not found"
    end
  end
end
