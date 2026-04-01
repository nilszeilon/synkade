defmodule Synkade.Execution.SessionEventCache do
  @moduledoc """
  In-memory ETS cache for agent session events.

  Stores events per issue_id so that LiveViews can restore them when
  re-mounting (e.g. navigating away and back). Events are cleared when
  the agent finishes or after a TTL expires.
  """
  use GenServer

  @table :session_event_cache
  @max_events 500

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Append events for an issue. Caps at #{@max_events} events."
  def append(issue_id, events) when is_list(events) do
    existing = get(issue_id)
    combined = Enum.take(existing ++ events, -@max_events)
    :ets.insert(@table, {issue_id, combined})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Get cached events for an issue."
  def get(issue_id) do
    case :ets.lookup(@table, issue_id) do
      [{^issue_id, events}] -> events
      [] -> []
    end
  rescue
    ArgumentError -> []
  end

  @doc """
  Get events for an issue, falling back to the agent's session storage
  if the ETS cache is empty (e.g. after app restart).
  """
  def get_or_load(issue_id, agent_kind, opts \\ []) do
    case get(issue_id) do
      [] ->
        session_id = opts[:session_id]
        workspace_path = opts[:workspace_path]

        if session_id do
          events = Synkade.Agent.SessionReader.load(agent_kind, session_id, workspace_path)

          # Cache the loaded events so we don't re-read from disk
          if events != [] do
            try do
              :ets.insert(@table, {issue_id, Enum.take(events, -@max_events)})
            rescue
              ArgumentError -> :ok
            end
          end

          events
        else
          []
        end

      events ->
        events
    end
  end

  @doc "Clear events for an issue (called when agent finishes)."
  def clear(issue_id) do
    :ets.delete(@table, issue_id)
    :ok
  rescue
    ArgumentError -> :ok
  end

  # --- GenServer ---

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end
end
