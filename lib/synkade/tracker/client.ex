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

  def fetch_pr_status(config, project_name, pr_number) do
    adapter = adapter_for(config)
    adapter.fetch_pr_status(config, project_name, pr_number)
  end

  def fetch_all_issues(config, project_name, opts \\ []) do
    adapter = adapter_for(config)
    adapter.fetch_all_issues(config, project_name, opts)
  end

  def add_issue_label(config, project_name, issue_id, label) do
    adapter = adapter_for(config)
    adapter.add_issue_label(config, project_name, issue_id, label)
  end

  def remove_issue_label(config, project_name, issue_id, label) do
    adapter = adapter_for(config)
    adapter.remove_issue_label(config, project_name, issue_id, label)
  end

  defp adapter_for(config) do
    kind = Config.tracker_kind(config)
    Map.get(@adapters, kind) || raise "Unsupported tracker kind: #{kind}"
  end
end
