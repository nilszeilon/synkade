defmodule SynkadeWeb.Api.StateControllerTest do
  use SynkadeWeb.ConnCase

  import Synkade.AccountsFixtures

  alias Synkade.Settings

  setup do
    scope = user_scope_fixture()
    {:ok, agent} = Settings.create_agent(scope, %{name: "state-test-agent"})
    {:ok, token} = Settings.generate_agent_token(agent)
    %{scope: scope, agent: agent, token: token}
  end

  defp auth_conn(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "GET /api/v1/agent/state" do
    test "returns state snapshot", %{conn: conn, token: token} do
      conn =
        conn
        |> auth_conn(token)
        |> get("/api/v1/agent/state")

      assert json = json_response(conn, 200)
      assert is_map(json["running"])
      assert is_map(json["agent_totals"])
    end
  end

  describe "GET /api/v1/agent/projects" do
    test "returns projects list", %{conn: conn, token: token} do
      conn =
        conn
        |> auth_conn(token)
        |> get("/api/v1/agent/projects")

      assert json = json_response(conn, 200)
      assert is_list(json["projects"])
    end
  end

  describe "GET /api/v1/agent/projects/:name" do
    test "returns 404 for unknown project", %{conn: conn, token: token} do
      conn =
        conn
        |> auth_conn(token)
        |> get("/api/v1/agent/projects/nonexistent")

      assert json_response(conn, 404)["error"] == "project not found"
    end
  end

  describe "POST /api/v1/agent/refresh" do
    test "returns ok", %{conn: conn, token: token} do
      conn =
        conn
        |> auth_conn(token)
        |> post("/api/v1/agent/refresh")

      assert json_response(conn, 200)["status"] == "ok"
    end
  end
end
