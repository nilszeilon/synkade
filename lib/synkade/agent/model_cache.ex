defmodule Synkade.Agent.ModelCache do
  @moduledoc "Simple ETS cache for fetched model lists. TTL-based expiry."
  use GenServer

  @table :model_cache
  @ttl_ms :timer.minutes(10)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Get cached models for a kind, or fetch and cache them."
  def get_or_fetch(kind, api_key) do
    case lookup(kind) do
      {:ok, models} ->
        {:ok, models}

      :miss ->
        case Synkade.Settings.Agent.fetch_models(kind, api_key) do
          {:ok, models} ->
            put(kind, models)
            {:ok, models}

          error ->
            error
        end
    end
  end

  @doc "Invalidate cache for a kind."
  def invalidate(kind) do
    :ets.delete(@table, kind)
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

  # --- Private ---

  defp lookup(kind) do
    case :ets.lookup(@table, kind) do
      [{^kind, models, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, models}
        else
          :miss
        end

      [] ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp put(kind, models) do
    expires_at = System.monotonic_time(:millisecond) + @ttl_ms
    :ets.insert(@table, {kind, models, expires_at})
  rescue
    ArgumentError -> :ok
  end
end
