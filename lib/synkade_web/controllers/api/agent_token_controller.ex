defmodule SynkadeWeb.Api.AgentTokenController do
  use SynkadeWeb, :controller

  alias Synkade.TokenUsage

  def create(conn, %{"model" => model, "input_tokens" => input, "output_tokens" => output})
      when is_binary(model) and is_integer(input) and is_integer(output) do
    agent = conn.assigns.current_agent
    TokenUsage.record_usage(agent.user_id, model, input, output)
    json(conn, %{ok: true})
  end

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "model (string), input_tokens (integer), and output_tokens (integer) are required"})
  end
end
