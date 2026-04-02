defmodule Synkade.Agent.Hermes do
  @moduledoc false
  @behaviour Synkade.Agent.Behaviour

  alias Synkade.Agent.{Event, PortHelper}
  alias Synkade.Workflow.Config

  require Logger

  @impl true
  def fetch_models(_api_key) do
    # Hermes supports multiple providers via OpenRouter, Anthropic, OpenAI, etc.
    # Model selection is typically done via `hermes model` or --model flag.
    # Return a curated list of commonly used models.
    {:ok,
     [
       {"Anthropic Claude Sonnet", "anthropic/claude-sonnet-4-20250514"},
       {"Anthropic Claude Haiku", "anthropic/claude-haiku-4-5-20251001"},
       {"OpenAI GPT-4o", "openai/gpt-4o"},
       {"OpenAI o3-mini", "openai/o3-mini"},
       {"Google Gemini 2.5 Pro", "google/gemini-2.5-pro"},
       {"DeepSeek V3", "deepseek/deepseek-chat"}
     ]}
  end

  @impl true
  def start_session(config, prompt, workspace_path) do
    args = build_args(config, prompt, [])
    run_agent(config, args, workspace_path)
  end

  @impl true
  def continue_session(config, nil, prompt, workspace_path) do
    start_session(config, prompt, workspace_path)
  end

  def continue_session(config, session_id, prompt, workspace_path) do
    args = build_args(config, prompt, ["--resume", session_id])
    run_agent(config, args, workspace_path)
  end

  @impl true
  defdelegate stop_session(session), to: Synkade.Agent.Client, as: :stop_port_session

  @impl true
  def build_args(config, prompt, extra_args) do
    model = Config.get(config, "agent", "model")

    args = ["chat", "-q", prompt, "--quiet"]

    args = if model, do: args ++ ["--model", model], else: args
    args = args ++ extra_args
    args
  end

  @impl true
  def build_env(config) do
    agent_env =
      case Config.get(config, "agent", "api_key") do
        nil -> []
        "" -> []
        key -> [{~c"OPENROUTER_API_KEY", String.to_charlist(key)}]
      end

    PortHelper.common_env(config, agent_env)
  end

  @impl true
  def parse_event(line) do
    case Jason.decode(line) do
      {:ok, data} ->
        case Synkade.Agent.ContentExpander.expand(data, &extract_session_id/1) do
          [] -> {:ok, build_event(data)}
          events -> {:ok, events}
        end

      {:error, _} ->
        :skip
    end
  end

  # --- Private ---

  defp run_agent(config, args, workspace_path) do
    env = build_env(config)
    Logger.info("Hermes: starting agent in #{workspace_path}")
    PortHelper.open_bash_port(config, args, workspace_path, env)
  rescue
    e ->
      Logger.error("Hermes: failed to start agent: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp build_event(data) do
    %Event{
      type: data["type"] || "unknown",
      session_id: extract_session_id(data),
      message: extract_message(data),
      model: data["model"] || get_in(data, ["usage", "model"]),
      input_tokens: get_in(data, ["usage", "input_tokens"]) || 0,
      output_tokens: get_in(data, ["usage", "output_tokens"]) || 0,
      total_tokens:
        (get_in(data, ["usage", "input_tokens"]) || 0) +
          (get_in(data, ["usage", "output_tokens"]) || 0),
      timestamp: DateTime.utc_now(),
      raw: data
    }
  end

  defp extract_session_id(data) do
    data["session_id"] || get_in(data, ["metadata", "session_id"])
  end

  defp extract_message(%{"type" => "assistant", "message" => msg}) when is_binary(msg), do: msg
  defp extract_message(%{"type" => "result", "result" => result}), do: result
  defp extract_message(%{"message" => msg}) when is_binary(msg), do: msg
  defp extract_message(_), do: nil
end
