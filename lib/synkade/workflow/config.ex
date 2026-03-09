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
      "app_id" => nil,
      "private_key" => nil,
      "private_key_path" => nil,
      "webhook_secret" => nil,
      "installation_id" => nil
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
      "max_turns" => 20,
      "max_retry_backoff_ms" => 300_000,
      "max_concurrent_agents_by_state" => %{},
      "stall_timeout_ms" => 300_000,
      "command" => nil,
      "allowed_tools" => ["Read", "Edit", "Write", "Bash", "Glob", "Grep"],
      "model" => nil,
      "append_system_prompt" => nil,
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
    },
    "linear" => %{
      "endpoint" => "https://api.linear.app/graphql",
      "active_states" => ["Todo", "In Progress"],
      "terminal_states" => ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
    }
  }

  @agent_command_defaults %{
    "claude" => "claude",
    "codex" => "codex app-server"
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

  @spec max_concurrent_agents(map()) :: pos_integer()
  def max_concurrent_agents(config) do
    to_pos_integer(get(config, "agent", "max_concurrent_agents"), 10)
  end

  @spec max_turns(map()) :: pos_integer()
  def max_turns(config), do: to_pos_integer(get(config, "agent", "max_turns"), 20)

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

  @spec auth_mode(map()) :: String.t()
  def auth_mode(config) do
    if get(config, "tracker", "app_id") do
      "app"
    else
      "pat"
    end
  end

  @spec private_key_pem(map()) :: String.t() | nil
  def private_key_pem(config) do
    case get(config, "tracker", "private_key") do
      nil ->
        case get(config, "tracker", "private_key_path") do
          nil -> nil
          path ->
            expanded = expand_path(path)
            case File.read(expanded) do
              {:ok, content} -> String.trim(content)
              {:error, _} -> nil
            end
        end

      pem ->
        pem
    end
  end

  @spec validate(map()) :: :ok | {:error, [String.t()]}
  def validate(config) do
    errors =
      []
      |> validate_tracker(config)
      |> validate_agent(config)
      |> validate_execution(config)
      |> validate_projects(config)

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
      if kind not in ["github", "linear"] do
        ["tracker.kind must be 'github' or 'linear', got: #{kind}" | errors]
      else
        errors
      end

    if kind == "github" do
      mode = auth_mode(config)

      if mode == "app" do
        errors = validate_app_auth(errors, config)
        errors
      else
        repo = get(config, "tracker", "repo")

        if is_nil(repo) or repo == "" do
          ["tracker.repo is required when tracker.kind is 'github' (PAT mode)" | errors]
        else
          errors
        end
      end
    else
      errors
    end
  end

  defp validate_app_auth(errors, config) do
    app_id = get(config, "tracker", "app_id")

    errors =
      if is_nil(app_id) or app_id == "" do
        ["tracker.app_id is required for GitHub App auth" | errors]
      else
        errors
      end

    pem = private_key_pem(config)

    if is_nil(pem) or pem == "" do
      ["tracker.private_key or tracker.private_key_path is required for GitHub App auth" | errors]
    else
      errors
    end
  end

  defp validate_agent(errors, config) do
    kind = agent_kind(config)

    if kind not in ["claude", "codex"] do
      ["agent.kind must be 'claude' or 'codex', got: #{kind}" | errors]
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

  defp validate_projects(errors, config) do
    case Map.get(config, "projects") do
      nil ->
        errors

      projects when is_list(projects) ->
        names = Enum.map(projects, &Map.get(&1, "name"))
        dupes = names -- Enum.uniq(names)

        errors =
          if dupes != [] do
            ["duplicate project names: #{Enum.join(Enum.uniq(dupes), ", ")}" | errors]
          else
            errors
          end

        enabled = Enum.filter(projects, &(Map.get(&1, "enabled", true) != false))

        if enabled == [] do
          ["at least one enabled project is required when projects is set" | errors]
        else
          errors
        end

      _ ->
        ["projects must be a list" | errors]
    end
  end
end
