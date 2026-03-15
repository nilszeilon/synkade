defmodule SynkadeWeb.Api.AgentMeControllerTest do
  use SynkadeWeb.ConnCase, async: true

  alias Synkade.Settings
  alias Synkade.Issues

  setup do
    {:ok, agent} = Settings.create_agent(%{name: "me-test-agent"})
    {:ok, token} = Settings.generate_agent_token(agent)

    {:ok, project} =
      Settings.create_project(%{name: "me-test-project", default_agent_id: agent.id})

    %{agent: agent, token: token, project: project}
  end

  defp auth_conn(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "GET /api/v1/agent/me" do
    test "returns agent identity and projects", %{
      conn: conn,
      token: token,
      agent: agent,
      project: project
    } do
      conn =
        conn
        |> auth_conn(token)
        |> get(~p"/api/v1/agent/me")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == agent.id
      assert data["name"] == "me-test-agent"
      assert data["kind"] == "claude"
      assert data["pull"] == false

      assert [%{"id" => project_id, "name" => "me-test-project"}] = data["projects"]
      assert project_id == project.id
    end

    test "includes projects where agent has assigned issues", %{
      conn: conn,
      token: token,
      agent: agent
    } do
      # Create a project where agent is NOT the default
      {:ok, other_project} = Settings.create_project(%{name: "me-assigned-project"})

      # Assign an issue to this agent in that project
      {:ok, _issue} =
        Issues.create_issue(%{
          body: "# Assigned issue",
          project_id: other_project.id,
          assigned_agent_id: agent.id
        })

      conn =
        conn
        |> auth_conn(token)
        |> get(~p"/api/v1/agent/me")

      assert %{"data" => data} = json_response(conn, 200)
      project_ids = Enum.map(data["projects"], & &1["id"])
      assert other_project.id in project_ids
    end

    test "returns 401 without token", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/agent/me")
      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end
end
