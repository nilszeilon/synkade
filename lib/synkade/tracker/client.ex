defmodule Synkade.Tracker.Client do
  @moduledoc false

  alias Synkade.Workflow.Config

  @adapters %{
    "github" => Synkade.Tracker.GitHub
  }

  def fetch_candidate_issues(config, project_name) do
    adapter = adapter_for(config)
    adapter.fetch_candidate_issues(config, project_name)
  end

  def fetch_issues_by_states(config, project_name, states) do
    adapter = adapter_for(config)
    adapter.fetch_issues_by_states(config, project_name, states)
  end

  def fetch_issue_states_by_ids(config, project_name, ids) do
    adapter = adapter_for(config)
    adapter.fetch_issue_states_by_ids(config, project_name, ids)
  end

  defp adapter_for(config) do
    kind = Config.tracker_kind(config)
    Map.get(@adapters, kind) || raise "Unsupported tracker kind: #{kind}"
  end
end
