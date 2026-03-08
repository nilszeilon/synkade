defmodule Synkade.Tracker.Behaviour do
  @moduledoc false

  alias Synkade.Tracker.Issue

  @callback fetch_candidate_issues(config :: map(), project_name :: String.t()) ::
              {:ok, [Issue.t()]} | {:error, term()}

  @callback fetch_issues_by_states(
              config :: map(),
              project_name :: String.t(),
              states :: [String.t()]
            ) ::
              {:ok, [Issue.t()]} | {:error, term()}

  @callback fetch_issue_states_by_ids(
              config :: map(),
              project_name :: String.t(),
              ids :: [String.t()]
            ) ::
              {:ok, %{String.t() => String.t()}} | {:error, term()}
end
