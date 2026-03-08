defmodule Synkade.Workflow.Watcher do
  @moduledoc false
  use GenServer

  require Logger

  alias Synkade.Workflow.Loader

  @pubsub_topic "workflow:updates"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def pubsub_topic, do: @pubsub_topic

  @doc "Get the current workflow."
  def get_workflow(server \\ __MODULE__) do
    GenServer.call(server, :get_workflow)
  end

  @doc "Force a reload."
  def reload(server \\ __MODULE__) do
    GenServer.call(server, :reload)
  end

  # --- Callbacks ---

  @impl true
  def init(opts) do
    path = opts[:path] || "WORKFLOW.md"
    pubsub = opts[:pubsub] || Synkade.PubSub

    state = %{
      path: path,
      pubsub: pubsub,
      workflow: nil,
      watcher_pid: nil,
      last_error: nil
    }

    case load_workflow(path) do
      {:ok, workflow} ->
        state = %{state | workflow: workflow}
        state = start_watching(state)
        {:ok, state}

      {:error, reason} ->
        Logger.warning("Workflow watcher: initial load failed: #{inspect(reason)}")
        state = %{state | last_error: reason}
        state = start_watching(state)
        {:ok, state}
    end
  end

  @impl true
  def handle_call(:get_workflow, _from, state) do
    {:reply, {:ok, state.workflow}, state}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    case load_workflow(state.path) do
      {:ok, workflow} ->
        state = %{state | workflow: workflow, last_error: nil}
        broadcast(state.pubsub, workflow)
        Logger.info("Workflow reloaded successfully")
        {:reply, {:ok, workflow}, state}

      {:error, reason} ->
        Logger.warning("Workflow reload failed: #{inspect(reason)}, keeping last-known-good config")
        {:reply, {:error, reason}, %{state | last_error: reason}}
    end
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, events}}, state) do
    if Path.basename(path) == Path.basename(state.path) and
         Enum.any?(events, &(&1 in [:modified, :created, :renamed])) do
      # Small delay to let file writes complete
      Process.send_after(self(), :do_reload, 100)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:do_reload, state) do
    case load_workflow(state.path) do
      {:ok, workflow} ->
        state = %{state | workflow: workflow, last_error: nil}
        broadcast(state.pubsub, workflow)
        Logger.info("Workflow reloaded from file change")
        {:noreply, state}

      {:error, reason} ->
        Logger.warning(
          "Workflow reload failed on file change: #{inspect(reason)}, keeping last-known-good config"
        )

        {:noreply, %{state | last_error: reason}}
    end
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    Logger.warning("File watcher stopped, attempting restart")
    state = start_watching(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private ---

  defp load_workflow(path) do
    Loader.load(path)
  end

  defp broadcast(pubsub, workflow) do
    Phoenix.PubSub.broadcast(pubsub, @pubsub_topic, {:workflow_reloaded, workflow})
  end

  defp start_watching(state) do
    dir = Path.dirname(Path.expand(state.path))

    case FileSystem.start_link(dirs: [dir]) do
      {:ok, pid} ->
        FileSystem.subscribe(pid)
        %{state | watcher_pid: pid}

      {:error, reason} ->
        Logger.warning("Failed to start file watcher: #{inspect(reason)}")
        state
    end
  end
end
