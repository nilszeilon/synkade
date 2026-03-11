defmodule Synkade.LogBroadcaster do
  @moduledoc """
  GenServer that owns ETS tables for log buffering and registers an OTP `:logger`
  handler to broadcast log entries via PubSub.
  """

  use GenServer

  @table :synkade_log_buffer
  @max_entries 500
  @counter :synkade_log_counter

  # ── Client API ──

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def topic, do: "logs:stream"

  def recent_entries(limit \\ @max_entries) do
    case :ets.whereis(@table) do
      :undefined ->
        []

      _ref ->
        :ets.tab2list(@table)
        |> Enum.map(fn {_id, entry} -> entry end)
        |> Enum.sort_by(& &1.id)
        |> Enum.take(-limit)
    end
  end

  # ── GenServer callbacks ──

  @impl true
  def init(_opts) do
    :ets.new(@table, [:ordered_set, :public, :named_table])
    :ets.new(@counter, [:set, :public, :named_table])
    :ets.insert(@counter, {:id, 0})

    :logger.add_handler(:synkade_log_broadcaster, __MODULE__, %{level: :info})

    {:ok, %{}}
  end

  # ── :logger handler callbacks ──

  def adding_handler(config), do: {:ok, config}

  def removing_handler(_config), do: :ok

  def changing_config(_action, _old, new), do: {:ok, new}

  def log(%{level: level, msg: msg, meta: meta}, _config) do
    message = format_message(msg)
    module = Map.get(meta, :mfa, nil) |> format_module()
    timestamp = Map.get(meta, :time) |> format_timestamp()

    id = :ets.update_counter(@counter, :id, 1)

    entry = %{
      id: id,
      level: level,
      message: message,
      timestamp: timestamp,
      module: module
    }

    :ets.insert(@table, {id, entry})
    trim_buffer()
    Phoenix.PubSub.broadcast(Synkade.PubSub, topic(), {:log_entry, entry})
    :ok
  catch
    _, _ -> :ok
  end

  # ── Helpers ──

  defp format_message({:string, msg}), do: IO.iodata_to_binary(msg)
  defp format_message({:report, report}), do: inspect(report)

  defp format_message({format, args}) when is_list(args) do
    format |> :io_lib.format(args) |> IO.iodata_to_binary()
  rescue
    _ -> inspect({format, args})
  end

  defp format_message(other), do: inspect(other)

  defp format_module({mod, _fun, _arity}), do: inspect(mod)
  defp format_module(nil), do: nil
  defp format_module(other), do: inspect(other)

  defp format_timestamp(nil), do: DateTime.utc_now()

  defp format_timestamp(microseconds) when is_integer(microseconds) do
    DateTime.from_unix!(microseconds, :microsecond)
  end

  defp trim_buffer do
    size = :ets.info(@table, :size)

    if size > @max_entries do
      first_key = :ets.first(@table)
      :ets.delete(@table, first_key)
      trim_buffer()
    end
  end
end
