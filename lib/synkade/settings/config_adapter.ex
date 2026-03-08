defmodule Synkade.Settings.ConfigAdapter do
  @moduledoc false

  alias Synkade.Settings.Setting

  @doc """
  Converts a Setting struct into the config map format consumed by
  Synkade.Workflow.Config and downstream modules.
  """
  def to_config(%Setting{} = s) do
    %{
      "tracker" => tracker_config(s),
      "agent" => agent_config(s)
    }
    |> maybe_put_prompt_template(s)
  end

  @doc """
  Deep-merges DB settings over file-based config. DB values win when present.
  """
  def merge_into(file_config, %Setting{} = s) do
    db_config = to_config(s)
    deep_merge(file_config, db_config)
  end

  defp tracker_config(%Setting{github_auth_mode: "pat"} = s) do
    %{
      "kind" => "github",
      "api_key" => s.github_pat,
      "repo" => s.github_repo,
      "endpoint" => s.github_endpoint,
      "labels" => non_empty_list(s.tracker_labels)
    }
    |> reject_nils()
  end

  defp tracker_config(%Setting{github_auth_mode: "app"} = s) do
    %{
      "kind" => "github",
      "app_id" => s.github_app_id,
      "private_key" => s.github_private_key,
      "webhook_secret" => s.github_webhook_secret,
      "installation_id" => s.github_installation_id,
      "endpoint" => s.github_endpoint,
      "labels" => non_empty_list(s.tracker_labels)
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

  defp maybe_put_prompt_template(config, %Setting{prompt_template: nil}), do: config
  defp maybe_put_prompt_template(config, %Setting{prompt_template: ""}), do: config

  defp maybe_put_prompt_template(config, %Setting{prompt_template: template}) do
    Map.put(config, "prompt_template", template)
  end

  defp non_empty_list(nil), do: nil
  defp non_empty_list([]), do: nil
  defp non_empty_list(list), do: list

  defp reject_nils(map) do
    Map.reject(map, fn {_k, v} -> is_nil(v) end)
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
