defmodule SynkadeWeb.Api.AgentIssuesControllerTest do
  use SynkadeWeb.ConnCase

  import Synkade.AccountsFixtures

  alias Synkade.Settings
  alias Synkade.Issues

  setup do
    scope = user_scope_fixture()
    {:ok, agent} = Settings.create_agent(scope, %{name: "api-test-agent"})
    {:ok, token} = Settings.generate_agent_token(agent)

    {:ok, project} =
      Settings.create_project(scope, %{name: "api-test-project", default_agent_id: agent.id})

    {:ok, issue} =
      Issues.create_issue(%{
        body: "# Test issue\n\nA test issue",
        project_id: project.id
      })

    %{agent: agent, token: token, project: project, issue: issue, scope: scope}
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

    test "returns cross-project inbox without project_id", %{
      conn: conn,
      token: token,
      issue: issue
    } do
      conn =
        conn
        |> auth_conn(token)
        |> get(~p"/api/v1/agent/issues")

      assert %{"data" => issues} = json_response(conn, 200)
      assert length(issues) >= 1
      assert Enum.any?(issues, fn i -> i["id"] == issue.id end)
    end

    test "returns 403 for unauthorized project", %{conn: conn, token: token, scope: scope} do
      {:ok, other_project} = Settings.create_project(scope, %{name: "other-project"})

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

    test "returns 403 for unauthorized project", %{conn: conn, token: token, scope: scope} do
      {:ok, other_project} = Settings.create_project(scope, %{name: "other-create-project"})

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

    test "transitions state for allowed agent transitions", %{
      conn: conn,
      token: token,
      project: project
    } do
      # Create an in_progress issue so we can transition to awaiting_review
      {:ok, issue} =
        Issues.create_issue(%{
          body: "# In progress issue",
          project_id: project.id,
          state: "backlog"
        })

      {:ok, issue} = Issues.transition_state(issue, "queued")
      {:ok, issue} = Issues.transition_state(issue, "in_progress")

      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/v1/agent/issues/#{issue.id}", %{state: "awaiting_review"})

      assert %{"data" => data} = json_response(conn, 200)
      assert data["state"] == "awaiting_review"
    end

    test "rejects agent transition to queued", %{conn: conn, token: token, issue: issue} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/v1/agent/issues/#{issue.id}", %{state: "queued"})

      assert json_response(conn, 403)["error"] == "agents cannot transition to this state"
    end

    test "rejects agent transition to cancelled", %{conn: conn, token: token, issue: issue} do
      conn =
        conn
        |> auth_conn(token)
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/v1/agent/issues/#{issue.id}", %{state: "cancelled"})

      assert json_response(conn, 403)["error"] == "agents cannot transition to this state"
    end

    test "rejects invalid state transition", %{conn: conn, token: token, issue: issue} do
      # backlog -> done is not valid
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

  # --- Checkout ---

  describe "POST /api/v1/agent/issues/:id/checkout" do
    test "atomically claims a queued issue", %{
      conn: conn,
      token: token,
      agent: agent,
      project: project
    } do
      {:ok, issue} =
        Issues.create_issue(%{body: "# Queued issue", project_id: project.id})

      {:ok, issue} = Issues.transition_state(issue, "queued")

      conn =
        conn
        |> auth_conn(token)
        |> post(~p"/api/v1/agent/issues/#{issue.id}/checkout")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["state"] == "in_progress"
      assert data["assigned_agent_id"] == agent.id
    end

    test "returns 409 when issue is not queued", %{
      conn: conn,
      token: token,
      issue: issue
    } do
      # issue is in backlog state
      conn =
        conn
        |> auth_conn(token)
        |> post(~p"/api/v1/agent/issues/#{issue.id}/checkout")

      assert json_response(conn, 409)["error"] == "issue is not in queued state"
    end

    test "returns 409 on double checkout (race condition)", %{
      conn: conn,
      token: token,
      project: project
    } do
      {:ok, issue} =
        Issues.create_issue(%{body: "# Race issue", project_id: project.id})

      {:ok, issue} = Issues.transition_state(issue, "queued")

      # First checkout succeeds
      conn1 =
        conn
        |> auth_conn(token)
        |> post(~p"/api/v1/agent/issues/#{issue.id}/checkout")

      assert json_response(conn1, 200)["data"]["state"] == "in_progress"

      # Second checkout fails with 409
      conn2 =
        build_conn()
        |> auth_conn(token)
        |> post(~p"/api/v1/agent/issues/#{issue.id}/checkout")

      assert json_response(conn2, 409)["error"] == "issue is not in queued state"
    end

    test "returns 404 for nonexistent issue", %{conn: conn, token: token} do
      conn =
        conn
        |> auth_conn(token)
        |> post(~p"/api/v1/agent/issues/#{Ecto.UUID.generate()}/checkout")

      assert json_response(conn, 404)["error"] == "not found"
    end

    test "returns 403 for unauthorized project", %{conn: conn, token: token, scope: scope} do
      {:ok, other_project} = Settings.create_project(scope, %{name: "checkout-other-project"})

      {:ok, issue} =
        Issues.create_issue(%{body: "# Other issue", project_id: other_project.id})

      {:ok, issue} = Issues.transition_state(issue, "queued")

      conn =
        conn
        |> auth_conn(token)
        |> post(~p"/api/v1/agent/issues/#{issue.id}/checkout")

      assert json_response(conn, 403)["error"] == "forbidden"
    end
  end

  # --- Cross-Project Inbox ---

  describe "GET /api/v1/agent/issues (cross-project)" do
    test "returns issues from all accessible projects", %{
      conn: conn,
      token: token,
      agent: agent,
      scope: scope
    } do
      {:ok, project2} =
        Settings.create_project(scope, %{name: "inbox-project-2", default_agent_id: agent.id})

      {:ok, issue2} =
        Issues.create_issue(%{body: "# Issue in project 2", project_id: project2.id})

      conn =
        conn
        |> auth_conn(token)
        |> get(~p"/api/v1/agent/issues")

      assert %{"data" => issues} = json_response(conn, 200)
      assert Enum.any?(issues, fn i -> i["id"] == issue2.id end)
    end

    test "filters by state across projects", %{
      conn: conn,
      token: token,
      agent: agent,
      scope: scope
    } do
      {:ok, project2} =
        Settings.create_project(scope, %{name: "inbox-filter-project", default_agent_id: agent.id})

      {:ok, issue} =
        Issues.create_issue(%{body: "# Queued inbox", project_id: project2.id})

      {:ok, _} = Issues.transition_state(issue, "queued")

      conn =
        conn
        |> auth_conn(token)
        |> get(~p"/api/v1/agent/issues?state=queued")

      assert %{"data" => issues} = json_response(conn, 200)
      assert Enum.all?(issues, fn i -> i["state"] == "queued" end)
    end

    test "filters by assigned_to=me across projects", %{
      conn: conn,
      token: token,
      agent: agent,
      scope: scope
    } do
      {:ok, project2} =
        Settings.create_project(scope, %{name: "inbox-assigned-project", default_agent_id: agent.id})

      {:ok, _assigned} =
        Issues.create_issue(%{
          body: "# Assigned issue",
          project_id: project2.id,
          assigned_agent_id: agent.id
        })

      {:ok, _unassigned} =
        Issues.create_issue(%{body: "# Unassigned issue", project_id: project2.id})

      conn =
        conn
        |> auth_conn(token)
        |> get(~p"/api/v1/agent/issues?assigned_to=me")

      assert %{"data" => issues} = json_response(conn, 200)
      assert Enum.all?(issues, fn i -> i["assigned_agent_id"] == agent.id end)
    end

    test "excludes issues from inaccessible projects", %{conn: conn, token: token, scope: scope} do
      {:ok, secret_project} = Settings.create_project(scope, %{name: "secret-project"})

      {:ok, secret_issue} =
        Issues.create_issue(%{body: "# Secret issue", project_id: secret_project.id})

      conn =
        conn
        |> auth_conn(token)
        |> get(~p"/api/v1/agent/issues")

      assert %{"data" => issues} = json_response(conn, 200)
      refute Enum.any?(issues, fn i -> i["id"] == secret_issue.id end)
    end
  end

  # --- JSON fields ---

  describe "JSON response includes project_id and assigned_agent_id" do
    test "issue summary includes project_id", %{
      conn: conn,
      token: token,
      project: project,
      issue: _issue
    } do
      conn =
        conn
        |> auth_conn(token)
        |> get(~p"/api/v1/agent/issues?project_id=#{project.id}")

      assert %{"data" => [first | _]} = json_response(conn, 200)
      assert first["project_id"] == project.id
      assert Map.has_key?(first, "assigned_agent_id")
    end

    test "issue detail includes project_id and assigned_agent_id", %{
      conn: conn,
      token: token,
      issue: issue,
      project: project
    } do
      conn =
        conn
        |> auth_conn(token)
        |> get(~p"/api/v1/agent/issues/#{issue.id}")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["project_id"] == project.id
      assert Map.has_key?(data, "assigned_agent_id")
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
