defmodule SynkadeWeb.Api.AgentIssuesJSON do
  @moduledoc false

  alias Synkade.Issues.Issue

  def issues(issues) do
    %{data: Enum.map(issues, &issue_summary/1)}
  end

  def issue(issue) do
    %{data: issue_detail(issue)}
  end

  defp issue_summary(issue) do
    %{
      id: issue.id,
      title: Issue.title(issue),
      state: issue.state,
      project_id: issue.project_id,
      assigned_agent_id: issue.assigned_agent_id,
      inserted_at: issue.inserted_at,
      updated_at: issue.updated_at
    }
  end

  defp issue_detail(issue) do
    %{
      id: issue.id,
      title: Issue.title(issue),
      body: issue.body,
      state: issue.state,
      project_id: issue.project_id,
      assigned_agent_id: issue.assigned_agent_id,
      agent_output: issue.agent_output,
      inserted_at: issue.inserted_at,
      updated_at: issue.updated_at
    }
  end
end
