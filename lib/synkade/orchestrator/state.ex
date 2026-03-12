defmodule Synkade.Orchestrator.State do
  @moduledoc false

  @type t :: %__MODULE__{
          projects: %{String.t() => map()},
          reconcile_interval_ms: pos_integer(),
          max_concurrent_agents: pos_integer(),
          running: %{String.t() => map()},
          claimed: MapSet.t(String.t()),
          retry_attempts: %{String.t() => map()},
          awaiting_review: %{String.t() => map()},
          agent_totals: %{
            input_tokens: non_neg_integer(),
            output_tokens: non_neg_integer(),
            total_tokens: non_neg_integer(),
            runtime_seconds: float()
          },
          agent_totals_by_project: %{String.t() => map()},
          agent_rate_limits: map() | nil,
          activity_log: list(%{project_name: String.t(), timestamp: DateTime.t()}),
          config_error: String.t() | nil
        }

  defstruct projects: %{},
            reconcile_interval_ms: 30_000,
            max_concurrent_agents: 10,
            running: %{},
            claimed: MapSet.new(),
            retry_attempts: %{},
            awaiting_review: %{},
            agent_totals: %{
              input_tokens: 0,
              output_tokens: 0,
              total_tokens: 0,
              runtime_seconds: 0.0
            },
            agent_totals_by_project: %{},
            agent_rate_limits: nil,
            activity_log: [],
            config_error: nil

  @doc "Build a composite key for an issue."
  @spec composite_key(String.t(), String.t()) :: String.t()
  def composite_key(project_name, issue_id), do: "#{project_name}:#{issue_id}"
end
