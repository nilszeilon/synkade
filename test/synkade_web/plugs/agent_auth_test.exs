defmodule SynkadeWeb.Plugs.AgentAuthTest do
  use SynkadeWeb.ConnCase

  import Synkade.AccountsFixtures

  alias Synkade.Settings

  setup do
    scope = user_scope_fixture()
    {:ok, agent} = Settings.create_agent(scope, %{name: "auth-test-agent"})
    {:ok, token} = Settings.generate_agent_token(agent)
    agent = Settings.get_agent!(agent.id)
    %{agent: agent, token: token, scope: scope}
  end

  test "authenticates with valid bearer token", %{conn: conn, token: token, agent: agent} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/v1/agent/issues?project_id=#{Ecto.UUID.generate()}")

    # Should not be 401 (may be 403 for invalid project, but auth passed)
    refute conn.status == 401
    assert conn.assigns[:current_agent].id == agent.id
  end

  test "returns 401 with invalid token", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer invalid_token")
      |> get(~p"/api/v1/agent/issues?project_id=#{Ecto.UUID.generate()}")

    assert conn.status == 401
    assert json_response(conn, 401)["error"] == "unauthorized"
  end

  test "returns 401 with missing authorization header", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/agent/issues?project_id=#{Ecto.UUID.generate()}")

    assert conn.status == 401
    assert json_response(conn, 401)["error"] == "unauthorized"
  end

  test "returns 401 after token is revoked", %{conn: conn, token: token, agent: agent, scope: scope} do
    {:ok, _} = Settings.revoke_agent_token(scope, agent)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/v1/agent/issues?project_id=#{Ecto.UUID.generate()}")

    assert conn.status == 401
  end
end
