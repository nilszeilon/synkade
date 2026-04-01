defmodule Synkade.AgentCooldowns do
  @moduledoc """
  ETS-based cooldown tracker for rate-limited agents.

  When an agent hits a rate limit, it's marked as cooled down for a
  configurable duration. The agent resolution chain skips cooled-down
  agents so the system can fall back to an available alternative.
  """

  use GenServer

  @table :agent_cooldowns
  @default_cooldown_seconds 3600

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Mark an agent as cooled down for `seconds` (default 1 hour)."
  def set_cooldown(agent_id, seconds \\ @default_cooldown_seconds) do
    expires_at = DateTime.add(DateTime.utc_now(), seconds, :second)
    :ets.insert(@table, {agent_id, expires_at})
    :ok
  end

  @doc "Check if an agent is currently in cooldown."
  def cooled_down?(agent_id) do
    case :ets.lookup(@table, agent_id) do
      [{^agent_id, expires_at}] ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          true
        else
          :ets.delete(@table, agent_id)
          false
        end

      [] ->
        false
    end
  end

  @doc "Clear cooldown for an agent."
  def clear_cooldown(agent_id) do
    :ets.delete(@table, agent_id)
    :ok
  end

  @doc "List all active cooldowns as `[{agent_id, expires_at}]`."
  def list_cooldowns do
    now = DateTime.utc_now()

    :ets.tab2list(@table)
    |> Enum.filter(fn {_id, expires_at} -> DateTime.compare(now, expires_at) == :lt end)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
end
