defmodule Synkade.Tracker.GitHub.InstallationRegistry do
  @moduledoc false
  use GenServer

  require Logger

  alias Synkade.Tracker.GitHub.{AppAuth, TokenServer}

  @refresh_interval_ms 5 * 60 * 1000
  @pubsub_topic "github:installations"

  defstruct [:app_id, :private_key_pem, :pubsub, repos: [], req_options: []]

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Returns the list of discovered repos."
  @spec list_repos(GenServer.server()) :: [%{repo: String.t(), installation_id: String.t() | integer()}]
  def list_repos(server \\ __MODULE__) do
    GenServer.call(server, :list_repos)
  end

  @doc "Triggers an immediate refresh of discovered repos."
  @spec refresh(GenServer.server()) :: :ok
  def refresh(server \\ __MODULE__) do
    GenServer.cast(server, :refresh)
  end

  def pubsub_topic, do: @pubsub_topic

  # --- Callbacks ---

  @impl true
  def init(opts) do
    state = %__MODULE__{
      app_id: Keyword.fetch!(opts, :app_id),
      private_key_pem: Keyword.fetch!(opts, :private_key_pem),
      pubsub: Keyword.get(opts, :pubsub, Synkade.PubSub),
      req_options: Keyword.get(opts, :req_options, [])
    }

    # Small delay to allow callers to configure test stubs
    Process.send_after(self(), :discover, 50)
    {:ok, state}
  end

  @impl true
  def handle_call(:list_repos, _from, state) do
    {:reply, state.repos, state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    state = do_discover(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:discover, state) do
    state = do_discover(state)
    schedule_refresh()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp do_discover(state) do
    case discover_repos(state) do
      {:ok, repos} ->
        if repos != state.repos do
          Phoenix.PubSub.broadcast(state.pubsub, @pubsub_topic, {:repos_changed, repos})
        end

        %{state | repos: repos}

      {:error, reason} ->
        Logger.warning("InstallationRegistry: discovery failed: #{inspect(reason)}")
        state
    end
  end

  defp discover_repos(state) do
    with {:ok, jwt} <- AppAuth.build_jwt(state.app_id, state.private_key_pem),
         {:ok, installations} <- AppAuth.list_installations(jwt, req_options: state.req_options) do
      repos =
        Enum.flat_map(installations, fn installation ->
          installation_id = installation["id"]

          case get_installation_token(installation_id, state) do
            {:ok, token} ->
              case AppAuth.list_installation_repos(token, req_options: state.req_options) do
                {:ok, repos} ->
                  Enum.map(repos, fn repo ->
                    %{repo: repo["full_name"], installation_id: installation_id}
                  end)

                {:error, reason} ->
                  Logger.warning("InstallationRegistry: failed to list repos for installation #{installation_id}: #{inspect(reason)}")
                  []
              end

            {:error, reason} ->
              Logger.warning("InstallationRegistry: failed to get token for installation #{installation_id}: #{inspect(reason)}")
              []
          end
        end)

      {:ok, repos}
    end
  end

  defp get_installation_token(installation_id, state) do
    case Registry.lookup(Synkade.TokenServerRegistry, installation_id) do
      [{_pid, _}] ->
        TokenServer.get_token(installation_id)

      [] ->
        # TokenServer not started yet — fetch directly
        with {:ok, jwt} <- AppAuth.build_jwt(state.app_id, state.private_key_pem),
             {:ok, %{token: token}} <-
               AppAuth.fetch_installation_token(jwt, installation_id, req_options: state.req_options) do
          {:ok, token}
        end
    end
  end

  defp schedule_refresh do
    Process.send_after(self(), :discover, @refresh_interval_ms)
  end
end
