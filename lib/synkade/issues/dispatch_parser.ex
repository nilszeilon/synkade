defmodule Synkade.Issues.DispatchParser do
  @moduledoc false

  @agent_regex ~r/^@(\w[\w-]*)\s+(.*)/s

  @spec parse(String.t()) :: {String.t() | nil, String.t()}
  def parse(message) do
    message = String.trim(message)

    case Regex.run(@agent_regex, message) do
      [_, agent_name, instruction] -> {agent_name, String.trim(instruction)}
      _ -> {nil, message}
    end
  end
end
