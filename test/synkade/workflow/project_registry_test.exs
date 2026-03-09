defmodule Synkade.Workflow.ProjectRegistryTest do
  use ExUnit.Case, async: true

  alias Synkade.Workflow.ProjectRegistry

  describe "resolve_projects/2" do
    test "single project mode with PAT config" do
      config = %{
        "tracker" => %{"kind" => "github", "repo" => "acme/api"},
        "agent" => %{"max_concurrent_agents" => 5}
      }

      [project] = ProjectRegistry.resolve_projects(config, "prompt")
      assert project.name == "api"
      assert project.prompt_template == "prompt"
      assert project.enabled == true
      assert project.config["tracker"]["repo"] == "acme/api"
    end

    test "defaults to 'default' name when no repo" do
      config = %{"tracker" => %{"kind" => "github"}}

      [project] = ProjectRegistry.resolve_projects(config, "prompt")
      assert project.name == "default"
    end
  end
end
