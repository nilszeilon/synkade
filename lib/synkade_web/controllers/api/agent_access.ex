defmodule SynkadeWeb.Api.AgentAccess do
  @moduledoc "Shared project access check for agent API controllers."

  import Ecto.Query

  alias Synkade.Settings

  @doc "Checks whether the given agent has access to the specified project."
  def has_project_access?(agent, project_id) do
    case Settings.get_project(project_id) do
      %{user_id: user_id, default_agent_id: agent_id}
      when agent_id == agent.id and user_id == agent.user_id ->
        true

      %{user_id: user_id} when user_id == agent.user_id ->
        project_has_agent_issues?(agent, project_id)

      _ ->
        false
    end
  end

  defp project_has_agent_issues?(agent, project_id) do
    Synkade.Repo.exists?(
      from(i in Synkade.Issues.Issue,
        where: i.project_id == ^project_id and i.assigned_agent_id == ^agent.id
      )
    )
  end
end
