defmodule SynkadeWeb.Api.StateController do
  use SynkadeWeb, :controller

  alias Synkade.Orchestrator

  def index(conn, _params) do
    state = Orchestrator.get_state()
    json(conn, SynkadeWeb.Api.StateJSON.state(state))
  end

  def projects(conn, _params) do
    state = Orchestrator.get_state()
    json(conn, SynkadeWeb.Api.StateJSON.projects(state))
  end

  def project(conn, %{"name" => name}) do
    state = Orchestrator.get_state()

    case Map.get(state.projects, name) do
      nil ->
        conn |> put_status(404) |> json(%{error: "project not found"})

      project ->
        json(conn, SynkadeWeb.Api.StateJSON.project(project, state))
    end
  end

  def refresh(conn, _params) do
    Orchestrator.refresh()
    json(conn, %{status: "ok"})
  end

end
