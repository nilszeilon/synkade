defmodule SynkadeWeb.Api.AgentMeController do
  use SynkadeWeb, :controller

  alias Synkade.Settings
  alias Synkade.Settings.Agent

  def show(conn, _params) do
    agent = conn.assigns.current_agent

    projects = Settings.list_agent_projects(agent.id)

    json(conn, %{
      data: %{
        id: agent.id,
        name: agent.name,
        kind: agent.kind,
        pull: Agent.pull_kind?(agent.kind),
        projects:
          Enum.map(projects, fn p ->
            %{id: p.id, name: p.name}
          end)
      }
    })
  end
end
