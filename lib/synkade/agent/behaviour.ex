defmodule Synkade.Agent.Behaviour do
  @moduledoc false

  alias Synkade.Agent.Event

  @type session :: %{
          session_id: String.t() | nil,
          port: port() | nil,
          os_pid: integer() | nil,
          events: [Event.t()]
        }

  @callback start_session(config :: map(), prompt :: String.t(), workspace_path :: String.t()) ::
              {:ok, session()} | {:error, term()}

  @callback continue_session(
              config :: map(),
              session_id :: String.t(),
              prompt :: String.t(),
              workspace_path :: String.t()
            ) ::
              {:ok, session()} | {:error, term()}

  @callback stop_session(session()) :: :ok

  @callback build_args(config :: map(), prompt :: String.t(), extra_args :: [String.t()]) ::
              [String.t()]

  @callback build_env(config :: map()) :: [{charlist(), charlist()}]

  @callback parse_event(line :: binary()) :: {:ok, Event.t()} | :skip

  @doc "Fetch available models from the provider API. Returns `{:ok, [{label, id}]}` or `{:error, reason}`."
  @callback fetch_models(api_key :: String.t()) ::
              {:ok, [{label :: String.t(), model_id :: String.t()}]} | {:error, term()}

  @optional_callbacks [fetch_models: 1]
end
