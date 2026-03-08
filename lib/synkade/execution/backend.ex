defmodule Synkade.Execution.Backend do
  @moduledoc false

  alias Synkade.Agent.Event

  @type env_ref :: term()
  @type session :: %{
          session_id: String.t() | nil,
          env_ref: env_ref(),
          events: [Event.t()],
          backend_data: map()
        }

  @callback setup_env(config :: map(), project_name :: String.t(), issue_identifier :: String.t()) ::
              {:ok, env_ref()} | {:error, term()}

  @callback run_before_hook(config :: map(), env_ref()) :: :ok | {:error, term()}

  @callback start_agent(config :: map(), prompt :: String.t(), env_ref()) ::
              {:ok, session()} | {:error, term()}

  @callback continue_agent(
              config :: map(),
              session_id :: String.t(),
              prompt :: String.t(),
              env_ref()
            ) ::
              {:ok, session()} | {:error, term()}

  @callback await_event(session(), timeout_ms :: non_neg_integer()) ::
              {:data, binary()} | {:exit, integer()} | :timeout

  @callback stop_agent(session()) :: :ok

  @callback run_after_hook(config :: map(), env_ref()) :: :ok

  @callback destroy_env(config :: map(), env_ref()) :: :ok

  @callback parse_event(binary()) :: {:ok, Event.t()} | :skip
end
