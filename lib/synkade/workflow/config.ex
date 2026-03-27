defmodule Synkade.Workflow.Config do
  @moduledoc false

  @defaults %{
    "tracker" => %{
      "kind" => "github",
      "endpoint" => nil,
      "api_key" => nil,
      "repo" => nil,
      "project_slug" => nil,
      "active_states" => nil,
      "terminal_states" => nil,
      "labels" => ["agent"],
      "assignee" => nil,
      "webhook_secret" => nil
    },
    "polling" => %{
      "interval_ms" => 30_000
    },
    "workspace" => %{
      "root" => nil
    },
    "hooks" => %{
      "after_create" => nil,
      "before_run" => nil,
      "after_run" => nil,
      "before_remove" => nil,
      "timeout_ms" => 60_000
    },
    "agent" => %{
      "kind" => "claude",
      "auth_mode" => "api_key",
      "api_key" => nil,
      "oauth_token" => nil,
      "max_concurrent_agents" => 10,
      "max_retry_backoff_ms" => 300_000,
      "max_concurrent_agents_by_state" => %{},
      "stall_timeout_ms" => 300_000,
      "command" => nil,
      "model" => nil,
      "turn_timeout_ms" => 3_600_000,
      "max_tokens" => nil
    },
    "execution" => %{
      "backend" => "local",
      "sprites_token" => nil,
      "sprites_org" => nil
    }
  }

  @tracker_defaults_by_kind %{
    "github" => %{
      "endpoint" => "https://api.github.com",
      "active_states" => ["open"],
      "terminal_states" => ["closed"]
    }
  }

  @agent_command_defaults %{
    "claude" => "claude",
    "codex" => "codex app-server",
    "opencode" => "opencode"
  }

  @spec get(map(), String.t(), String.t()) :: term()
  def get(config, section, key) do
    raw = get_in(config, [section, key])

    resolved =
      case raw do
        nil -> get_default(config, section, key)
        value -> value
      end

    resolve_env(resolved)
  end

  @spec get_section(map(), String.t()) :: map()
  def get_section(config, section) do
    section_defaults = Map.get(@defaults, section, %{})
    raw_section = Map.get(config, section, %{}) || %{}

    merged =
      Map.merge(section_defaults, raw_section, fn _k, default_val, override ->
        if is_nil(override), do: default_val, else: override
      end)

    Map.new(merged, fn {k, v} ->
      resolved = resolve_env(v)

      final =
        if is_nil(resolved) do
          get_default(config, section, k)
        else
          resolved
        end

      {k, final}
    end)
  end

  @spec workspace_root(map()) :: String.t()
  def workspace_root(config) do
    raw = get(config, "workspace", "root")

    case raw do
      nil -> Path.join(System.tmp_dir!(), "synkade_workspaces")
      path -> expand_path(path)
    end
  end

  @spec poll_interval_ms(map()) :: pos_integer()
  def poll_interval_ms(config) do
    to_pos_integer(get(config, "polling", "interval_ms"), 30_000)
  end

  @spec reconcile_interval_ms(map()) :: pos_integer()
  def reconcile_interval_ms(config), do: poll_interval_ms(config)

  @spec max_concurrent_agents(map()) :: pos_integer()
  def max_concurrent_agents(config) do
    to_pos_integer(get(config, "agent", "max_concurrent_agents"), 10)
  end

  @spec max_retry_backoff_ms(map()) :: pos_integer()
  def max_retry_backoff_ms(config) do
    to_pos_integer(get(config, "agent", "max_retry_backoff_ms"), 300_000)
  end

  @spec execution_backend(map()) :: String.t()
  def execution_backend(config), do: get(config, "execution", "backend") || "local"

  @spec agent_kind(map()) :: String.t()
  def agent_kind(config), do: get(config, "agent", "kind") || "claude"

  @spec agent_command(map()) :: String.t()
  def agent_command(config) do
    cmd = get(config, "agent", "command")
    kind = agent_kind(config)
    cmd || Map.get(@agent_command_defaults, kind, "claude")
  end

  @spec tracker_kind(map()) :: String.t()
  def tracker_kind(config), do: get(config, "tracker", "kind") || "github"

  @spec active_states(map()) :: [String.t()]
  def active_states(config) do
    raw = get(config, "tracker", "active_states")
    normalize_string_list(raw) || tracker_kind_default(config, "active_states")
  end

  @spec terminal_states(map()) :: [String.t()]
  def terminal_states(config) do
    raw = get(config, "tracker", "terminal_states")
    normalize_string_list(raw) || tracker_kind_default(config, "terminal_states")
  end

  @spec tracker_labels(map()) :: [String.t()] | nil
  def tracker_labels(config) do
    raw = get(config, "tracker", "labels")
    normalize_string_list(raw)
  end

  @spec validate(map()) :: :ok | {:error, [String.t()]}
  def validate(config) do
    errors =
      []
      |> validate_tracker(config)
      |> validate_agent(config)
      |> validate_execution(config)

    case errors do
      [] -> :ok
      errs -> {:error, Enum.reverse(errs)}
    end
  end

  # --- Private ---

  defp get_default(config, "tracker", key) do
    kind = get_in(config, ["tracker", "kind"]) || "github"
    kind_defaults = Map.get(@tracker_defaults_by_kind, kind, %{})
    Map.get(kind_defaults, key) || Map.get(Map.get(@defaults, "tracker", %{}), key)
  end

  defp get_default(config, "agent", "command") do
    kind = get_in(config, ["agent", "kind"]) || "claude"
    Map.get(@agent_command_defaults, kind, "claude")
  end

  defp get_default(_config, section, key) do
    Map.get(Map.get(@defaults, section, %{}), key)
  end

  defp tracker_kind_default(config, field) do
    kind = tracker_kind(config)
    kind_defaults = Map.get(@tracker_defaults_by_kind, kind, %{})
    normalize_string_list(Map.get(kind_defaults, field)) || []
  end

  @spec resolve_env(term()) :: term()
  def resolve_env("$" <> var_name) do
    case System.get_env(var_name) do
      nil -> nil
      "" -> nil
      value -> value
    end
  end

  def resolve_env(value), do: value

  @spec expand_path(String.t()) :: String.t()
  def expand_path("~/" <> rest), do: Path.join(System.user_home!(), rest)
  def expand_path("~"), do: System.user_home!()
  def expand_path(path), do: path

  defp normalize_string_list(nil), do: nil
  defp normalize_string_list(list) when is_list(list), do: list

  defp normalize_string_list(str) when is_binary(str) do
    str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp normalize_string_list(_), do: nil

  defp to_pos_integer(val, _default) when is_integer(val) and val > 0, do: val

  defp to_pos_integer(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end

  defp to_pos_integer(_, default), do: default

  defp validate_tracker(errors, config) do
    kind = tracker_kind(config)

    errors =
      if kind != "github" do
        ["tracker.kind must be 'github', got: #{kind}" | errors]
      else
        errors
      end

    repo = get(config, "tracker", "repo")

    if is_nil(repo) or repo == "" do
      ["tracker.repo is required" | errors]
    else
      errors
    end
  end

  defp validate_agent(errors, config) do
    kind = agent_kind(config)

    if kind not in ["claude", "codex", "opencode"] do
      ["agent.kind must be 'claude', 'codex', or 'opencode', got: #{kind}" | errors]
    else
      errors
    end
  end

  defp validate_execution(errors, config) do
    backend = execution_backend(config)

    errors =
      if backend not in ["local", "sprites"] do
        ["execution.backend must be 'local' or 'sprites', got: #{backend}" | errors]
      else
        errors
      end

    if backend == "sprites" do
      token = get(config, "execution", "sprites_token")

      if is_nil(token) or token == "" do
        ["execution.sprites_token is required when execution.backend is 'sprites'" | errors]
      else
        errors
      end
    else
      errors
    end
  end
end
