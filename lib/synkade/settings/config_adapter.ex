defmodule Synkade.Settings.ConfigAdapter do
  @moduledoc false

  alias Synkade.Settings.{Setting, Project, Agent}

  @doc """
  Converts a Setting struct into the config map format consumed by
  Synkade.Workflow.Config and downstream modules.

  No longer includes an "agent" section — agent config comes from Agent structs.
  """
  def to_config(%Setting{} = s) do
    %{
      "tracker" => tracker_config(s),
      "execution" => execution_config(s)
    }
  end

  @doc """
  Converts an Agent struct into the agent config map.
  """
  def agent_to_config(%Agent{} = a) do
    %{
      "kind" => a.kind,
      "auth_mode" => a.auth_mode,
      "api_key" => a.api_key,
      "oauth_token" => a.oauth_token,
      "model" => a.model,
      "max_turns" => a.max_turns,
      "allowed_tools" => non_empty_list(a.allowed_tools),
      "system_prompt" => a.system_prompt,
      "synkade_api_token" => a.api_token
    }
    |> reject_nils()
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
  with per-project overrides and agent config. Project values win when present.
  """
  def resolve_project_config(%Setting{} = global, %Project{} = project, %Agent{} = agent) do
    global_config = to_config(global)
    project_config = project_to_config(project)
    agent_config = agent_to_config(agent)

    deep_merge(global_config, project_config)
    |> Map.put("agent", agent_config)
    |> Map.put("user_id", project.user_id)
    |> Map.put("project_id", project.id)
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

  defp execution_config(%Setting{} = s) do
    if Synkade.Deployment.hosted?() do
      %{
        "backend" => "sprites",
        "sprites_token" => System.get_env("SPRITES_TOKEN"),
        "sprites_org" => System.get_env("SPRITES_ORG")
      }
    else
      %{
        "backend" => s.execution_backend,
        "sprites_token" => s.execution_sprites_token,
        "sprites_org" => s.execution_sprites_org
      }
    end
    |> reject_nils()
  end

  # --- Project → config ---

  defp project_tracker_config(%Project{} = p) do
    %{
      "repo" => p.tracker_repo
    }
    |> reject_nils()
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
