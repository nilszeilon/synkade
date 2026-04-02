defmodule Synkade.Agent.OpenCode do
  @moduledoc false
  @behaviour Synkade.Agent.Behaviour

  alias Synkade.Agent.{Event, PortHelper}
  alias Synkade.Workflow.Config

  require Logger

  @fetch_timeout 15_000

  @impl true
  def fetch_models(_api_key) do
    task =
      Task.async(fn ->
        opencode = System.find_executable("opencode") || "opencode"

        case System.cmd("bash", ["-lc", "#{opencode} models"],
               stderr_to_stdout: true,
               env: [{"NO_COLOR", "1"}]
             ) do
          {output, 0} ->
            items =
              output
              |> String.split("\n", trim: true)
              |> Enum.map(&String.trim/1)
              |> Enum.reject(&(&1 == ""))
              |> Enum.map(fn model_id -> {model_id, model_id} end)

            {:ok, items}

          {output, _code} ->
            {:error, "opencode models failed: #{String.slice(output, 0..200)}"}
        end
      end)

    Task.await(task, @fetch_timeout)
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def start_session(config, prompt, workspace_path) do
    args = build_args(config, prompt, [])
    run_agent(config, args, workspace_path)
  end

  @impl true
  def continue_session(config, _session_id, prompt, workspace_path) do
    args = build_args(config, prompt, ["--continue"])
    run_agent(config, args, workspace_path)
  end

  @impl true
  defdelegate stop_session(session), to: Synkade.Agent.Client, as: :stop_port_session

  @impl true
  def build_args(config, prompt, extra_args) do
    model = Config.get(config, "agent", "model")

    args = ["run", "--format", "json", "--thinking"]

    args = if model, do: args ++ ["--model", model], else: args

    args ++ extra_args ++ [prompt]
  end

  # Map model prefix to the env var OpenCode expects for that provider
  @provider_env_vars %{
    "fireworks-ai" => "FIREWORKS_API_KEY",
    "openrouter" => "OPENROUTER_API_KEY",
    "anthropic" => "ANTHROPIC_API_KEY",
    "openai" => "OPENAI_API_KEY",
    "google" => "GOOGLE_GENERATIVE_AI_API_KEY",
    "deepseek" => "DEEPSEEK_API_KEY",
    "groq" => "GROQ_API_KEY",
    "mistral" => "MISTRAL_API_KEY",
    "xai" => "XAI_API_KEY",
    "together" => "TOGETHER_API_KEY"
  }

  @impl true
  def build_env(config) do
    agent_env =
      case Config.get(config, "agent", "api_key") do
        nil ->
          []

        "" ->
          []

        key ->
          env_var = api_key_env_var(Config.get(config, "agent", "model"))
          [{String.to_charlist(env_var), String.to_charlist(key)}]
      end

    PortHelper.common_env(config, agent_env)
  end

  @impl true
  def parse_event(line) do
    case Jason.decode(line) do
      {:ok, data} ->
        {:ok, build_event(data)}

      {:error, _} ->
        :skip
    end
  end

  # --- Private ---

  defp run_agent(config, args, workspace_path) do
    env = build_env(config)
    Logger.info("OpenCode: starting agent in #{workspace_path}")
    PortHelper.open_bash_port(config, args, workspace_path, env)
  rescue
    e ->
      Logger.error("OpenCode: failed to start agent: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp api_key_env_var(nil), do: "OPENROUTER_API_KEY"

  defp api_key_env_var(model) when is_binary(model) do
    case String.split(model, "/", parts: 2) do
      [provider, _rest] -> Map.get(@provider_env_vars, provider, "OPENROUTER_API_KEY")
      _ -> "OPENROUTER_API_KEY"
    end
  end

  defp build_event(data) do
    # OpenCode tokens live inside part.tokens on step_finish events
    tokens = get_in(data, ["part", "tokens"]) || %{}

    # Normalize reasoning to thinking for unified UI
    type =
      case data["type"] do
        "reasoning" -> "thinking"
        other -> other || "unknown"
      end

    %Event{
      type: type,
      session_id: data["sessionID"],
      message: extract_message(data),
      model: data["model"] || get_in(data, ["part", "model"]),
      input_tokens: tokens["input"] || 0,
      output_tokens: tokens["output"] || 0,
      total_tokens: tokens["total"] || 0,
      timestamp: DateTime.utc_now(),
      raw: data
    }
  end

  # OpenCode step_finish carries reason in part.reason
  defp extract_message(%{"type" => "step_finish", "part" => %{"reason" => reason}}), do: reason
  # OpenCode events: text nested in part.text or at top level
  defp extract_message(%{"part" => %{"text" => text}}) when is_binary(text), do: text
  defp extract_message(%{"type" => "error", "error" => %{"data" => %{"message" => msg}}}), do: msg
  defp extract_message(%{"type" => "error", "error" => %{"message" => msg}}), do: msg
  defp extract_message(%{"text" => text}) when is_binary(text), do: text
  defp extract_message(%{"message" => msg}) when is_binary(msg), do: msg
  defp extract_message(_), do: nil
end
