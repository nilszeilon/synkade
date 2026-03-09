defmodule Synkade.Workflow.ProjectRegistry do
  @moduledoc false

  alias Synkade.Workflow.Config

  @merge_sections ["tracker", "agent", "execution", "workspace", "kanban"]

  @spec resolve_projects(map(), String.t()) :: [map()]
  def resolve_projects(config, prompt_template) do
    case Map.get(config, "projects") do
      nil ->
        if Config.auth_mode(config) == "app" do
          build_app_discovered_projects(config, prompt_template)
        else
          [build_single_project(config, prompt_template)]
        end

      projects when is_list(projects) ->
        Enum.map(projects, &resolve_project(&1, config, prompt_template))

      _ ->
        [build_single_project(config, prompt_template)]
    end
  end

  @spec resolve_project(map(), map(), String.t()) :: map()
  def resolve_project(project_entry, global_config, global_prompt) do
    name = Map.fetch!(project_entry, "name")

    effective_config =
      Enum.reduce(@merge_sections, %{}, fn section, acc ->
        global_section = Map.get(global_config, section, %{}) || %{}
        project_section = Map.get(project_entry, section, %{}) || %{}
        merged = Map.merge(global_section, project_section)
        Map.put(acc, section, merged)
      end)

    # Hooks replace rather than merge
    effective_config =
      case Map.get(project_entry, "hooks") do
        nil -> Map.put(effective_config, "hooks", Map.get(global_config, "hooks", %{}) || %{})
        hooks -> Map.put(effective_config, "hooks", hooks)
      end

    # Polling is always global
    effective_config =
      Map.put(effective_config, "polling", Map.get(global_config, "polling", %{}) || %{})

    prompt = Map.get(project_entry, "prompt", global_prompt)

    max_concurrent =
      Map.get(project_entry, "max_concurrent_agents") ||
        Config.max_concurrent_agents(effective_config)

    %{
      name: name,
      config: effective_config,
      prompt_template: prompt,
      max_concurrent_agents: max_concurrent,
      enabled: Map.get(project_entry, "enabled", true) != false
    }
  end

  defp build_app_discovered_projects(config, prompt_template) do
    alias Synkade.Tracker.GitHub.InstallationRegistry

    repos = InstallationRegistry.list_repos()

    if repos == [] do
      [build_single_project(config, prompt_template)]
    else
      Enum.map(repos, fn %{repo: repo, installation_id: installation_id} ->
        name = repo |> String.split("/") |> List.last() || repo

        project_config =
          config
          |> put_in(["tracker", "repo"], repo)
          |> put_in(["tracker", "installation_id"], installation_id)

        %{
          name: name,
          config: project_config,
          prompt_template: prompt_template,
          max_concurrent_agents: Config.max_concurrent_agents(project_config),
          enabled: true
        }
      end)
    end
  end

  defp build_single_project(config, prompt_template) do
    repo = Config.get(config, "tracker", "repo")

    name =
      if repo do
        repo |> String.split("/") |> List.last() || "default"
      else
        "default"
      end

    %{
      name: name,
      config: config,
      prompt_template: prompt_template,
      max_concurrent_agents: Config.max_concurrent_agents(config),
      enabled: true
    }
  end
end
