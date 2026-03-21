defmodule SynkadeWeb.Api.StateController do
  use SynkadeWeb, :controller

  alias Synkade.Jobs
  alias Synkade.Accounts.Scope

  defp scope_from_agent(conn) do
    agent = conn.assigns.current_agent
    user = Synkade.Repo.get!(Synkade.Accounts.User, agent.user_id)
    Scope.for_user(user)
  end

  def index(conn, _params) do
    scope = scope_from_agent(conn)
    state = Jobs.get_state(scope)
    json(conn, SynkadeWeb.Api.StateJSON.state(state))
  end

  def projects(conn, _params) do
    scope = scope_from_agent(conn)
    state = Jobs.get_state(scope)
    json(conn, SynkadeWeb.Api.StateJSON.projects(state))
  end

  def project(conn, %{"name" => name}) do
    scope = scope_from_agent(conn)
    state = Jobs.get_state(scope)

    case Map.get(state.projects, name) do
      nil ->
        conn |> put_status(404) |> json(%{error: "project not found"})

      project ->
        json(conn, SynkadeWeb.Api.StateJSON.project(project, state))
    end
  end

  def refresh(conn, _params) do
    scope = scope_from_agent(conn)
    Jobs.refresh(scope)
    json(conn, %{status: "ok"})
  end
end
