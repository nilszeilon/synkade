defmodule Synkade.Tracker.GitHub.TokenServer do
  @moduledoc false
  use GenServer

  require Logger

  alias Synkade.Tracker.GitHub.AppAuth

  @refresh_buffer_ms 5 * 60 * 1000

  defstruct [:installation_id, :app_id, :private_key_pem, :token, :expires_at, :refresh_timer, req_options: []]

  def start_link(opts) do
    installation_id = Keyword.fetch!(opts, :installation_id)
    name = {:via, Registry, {Synkade.TokenServerRegistry, installation_id}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Get a valid installation token. Fetches or returns cached."
  @spec get_token(String.t() | integer()) :: {:ok, String.t()} | {:error, term()}
  def get_token(installation_id) do
    name = {:via, Registry, {Synkade.TokenServerRegistry, installation_id}}
    GenServer.call(name, :get_token)
  end

  # --- Callbacks ---

  @impl true
  def init(opts) do
    state = %__MODULE__{
      installation_id: Keyword.fetch!(opts, :installation_id),
      app_id: Keyword.fetch!(opts, :app_id),
      private_key_pem: Keyword.fetch!(opts, :private_key_pem),
      req_options: Keyword.get(opts, :req_options, [])
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_token, _from, state) do
    if token_valid?(state) do
      {:reply, {:ok, state.token}, state}
    else
      case fetch_new_token(state) do
        {:ok, new_state} ->
          {:reply, {:ok, new_state.token}, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_info(:refresh_token, state) do
    case fetch_new_token(state) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("TokenServer: failed to refresh token for installation #{state.installation_id}: #{inspect(reason)}")
        {:noreply, %{state | token: nil, expires_at: nil}}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp token_valid?(%{token: nil}), do: false

  defp token_valid?(%{expires_at: expires_at}) do
    now = DateTime.utc_now()
    buffer = @refresh_buffer_ms / 1000
    DateTime.diff(expires_at, now) > buffer
  end

  defp fetch_new_token(state) do
    with {:ok, jwt} <- AppAuth.build_jwt(state.app_id, state.private_key_pem),
         {:ok, %{token: token, expires_at: expires_at}} <-
           AppAuth.fetch_installation_token(jwt, state.installation_id, req_options: state.req_options) do
      # Cancel existing timer
      if state.refresh_timer, do: Process.cancel_timer(state.refresh_timer)

      # Schedule proactive refresh
      ms_until_refresh = max(DateTime.diff(expires_at, DateTime.utc_now(), :millisecond) - @refresh_buffer_ms, 1000)
      timer = Process.send_after(self(), :refresh_token, ms_until_refresh)

      {:ok, %{state | token: token, expires_at: expires_at, refresh_timer: timer}}
    end
  end
end
