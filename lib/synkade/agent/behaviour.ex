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
end
