defmodule Synkade.Workflow.ProjectRegistry do
  @moduledoc false

  alias Synkade.Workflow.Config

  @spec resolve_projects(map(), String.t()) :: [map()]
  def resolve_projects(config, prompt_template) do
    if Config.auth_mode(config) == "app" do
      build_app_discovered_projects(config, prompt_template)
    else
      [build_single_project(config, prompt_template)]
    end
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
