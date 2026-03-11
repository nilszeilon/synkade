defmodule SynkadeWeb.Api.AgentIssuesJSON do
  @moduledoc false

  def issues(issues) do
    %{data: Enum.map(issues, &issue_summary/1)}
  end

  def issue(issue) do
    %{data: issue_detail(issue)}
  end

  defp issue_summary(issue) do
    %{
      id: issue.id,
      title: issue.title,
      state: issue.state,
      priority: issue.priority,
      parent_id: issue.parent_id,
      inserted_at: issue.inserted_at,
      updated_at: issue.updated_at
    }
  end

  defp issue_detail(issue) do
    children =
      case issue.children do
        %Ecto.Association.NotLoaded{} -> []
        list -> Enum.map(list, &issue_summary/1)
      end

    %{
      id: issue.id,
      title: issue.title,
      description: issue.description,
      state: issue.state,
      priority: issue.priority,
      depth: issue.depth,
      parent_id: issue.parent_id,
      agent_output: issue.agent_output,
      children: children,
      inserted_at: issue.inserted_at,
      updated_at: issue.updated_at
    }
  end
end
