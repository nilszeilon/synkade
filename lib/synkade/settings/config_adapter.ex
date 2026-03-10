defmodule Synkade.Settings.ConfigAdapter do
  @moduledoc false

  alias Synkade.Settings.{Setting, Project}

  @doc """
  Converts a Setting struct into the config map format consumed by
  Synkade.Workflow.Config and downstream modules.
  """
  def to_config(%Setting{} = s) do
    %{
      "tracker" => tracker_config(s),
      "agent" => agent_config(s),
      "execution" => execution_config(s)
    }
    |> maybe_put_prompt_template(s)
  end

  @doc """
  Converts a Project struct into a config map, omitting nil values.
  Same format as to_config/1 but only includes fields the project overrides.
  """
  def project_to_config(%Project{} = p) do
    %{
      "tracker" => project_tracker_config(p)
    }
    |> reject_empty_sections()
    |> maybe_put_project_prompt(p)
  end

  @doc """
  Resolves the effective config for a project by deep-merging global settings
  with per-project overrides. Project values win when present.
  """
  def resolve_project_config(%Setting{} = global, %Project{} = project) do
    global_config = to_config(global)
    project_config = project_to_config(project)
    deep_merge(global_config, project_config)
  end

  # --- Setting → config ---

  defp tracker_config(%Setting{} = s) do
    %{
      "kind" => "github",
      "api_key" => s.github_pat,
      "webhook_secret" => s.github_webhook_secret
    }
    |> reject_nils()
  end

  defp agent_config(%Setting{} = s) do
    %{
      "kind" => s.agent_kind,
      "auth_mode" => s.agent_auth_mode,
      "api_key" => s.agent_api_key,
      "oauth_token" => s.agent_oauth_token,
      "model" => s.agent_model,
      "max_turns" => s.agent_max_turns,
      "allowed_tools" => non_empty_list(s.agent_allowed_tools),
      "max_concurrent_agents" => s.agent_max_concurrent
    }
    |> reject_nils()
  end

  defp execution_config(%Setting{} = s) do
    %{
      "backend" => s.execution_backend,
      "sprites_token" => s.execution_sprites_token,
      "sprites_org" => s.execution_sprites_org
    }
    |> reject_nils()
  end

  # --- Project → config ---

  defp project_tracker_config(%Project{} = p) do
    %{
      "repo" => p.tracker_repo
    }
    |> reject_nils()
  end

  defp maybe_put_prompt_template(config, %Setting{prompt_template: nil}), do: config
  defp maybe_put_prompt_template(config, %Setting{prompt_template: ""}), do: config

  defp maybe_put_prompt_template(config, %Setting{prompt_template: template}) do
    Map.put(config, "prompt_template", template)
  end

  defp maybe_put_project_prompt(config, %Project{prompt_template: nil}), do: config
  defp maybe_put_project_prompt(config, %Project{prompt_template: ""}), do: config

  defp maybe_put_project_prompt(config, %Project{prompt_template: template}) do
    Map.put(config, "prompt_template", template)
  end

  defp non_empty_list(nil), do: nil
  defp non_empty_list([]), do: nil
  defp non_empty_list(list), do: list

  defp reject_nils(map) do
    Map.reject(map, fn {_k, v} -> is_nil(v) end)
  end

  defp reject_empty_sections(map) do
    Map.reject(map, fn {_k, v} -> is_map(v) and map_size(v) == 0 end)
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn
      _key, left_val, right_val when is_map(left_val) and is_map(right_val) ->
        deep_merge(left_val, right_val)

      _key, _left_val, right_val ->
        right_val
    end)
  end

  defp deep_merge(_left, right), do: right
end
