defmodule Synkade.Workflow.ProjectRegistryTest do
  use ExUnit.Case, async: true

  alias Synkade.Workflow.ProjectRegistry

  describe "resolve_projects/2" do
    test "single project mode when no projects key" do
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

    test "multi-project mode merges global defaults" do
      config = %{
        "agent" => %{"kind" => "claude", "max_turns" => 10},
        "workspace" => %{"root" => "/tmp/ws"},
        "projects" => [
          %{
            "name" => "api",
            "tracker" => %{"kind" => "github", "repo" => "acme/api"},
            "agent" => %{"model" => "claude-sonnet-4-5-20250929"}
          },
          %{
            "name" => "web",
            "tracker" => %{"kind" => "github", "repo" => "acme/web"}
          }
        ]
      }

      projects = ProjectRegistry.resolve_projects(config, "global prompt")
      assert length(projects) == 2

      api = Enum.find(projects, &(&1.name == "api"))
      assert api.config["agent"]["kind"] == "claude"
      assert api.config["agent"]["model"] == "claude-sonnet-4-5-20250929"
      assert api.config["agent"]["max_turns"] == 10
      assert api.config["workspace"]["root"] == "/tmp/ws"

      web = Enum.find(projects, &(&1.name == "web"))
      assert web.config["agent"]["kind"] == "claude"
      assert web.config["agent"]["model"] == nil
    end

    test "hooks replace rather than merge" do
      config = %{
        "hooks" => %{"after_create" => "global_hook", "before_run" => "global_before"},
        "projects" => [
          %{
            "name" => "api",
            "tracker" => %{"kind" => "github", "repo" => "acme/api"},
            "hooks" => %{"after_create" => "project_hook"}
          },
          %{
            "name" => "web",
            "tracker" => %{"kind" => "github", "repo" => "acme/web"}
          }
        ]
      }

      projects = ProjectRegistry.resolve_projects(config, "prompt")

      api = Enum.find(projects, &(&1.name == "api"))
      assert api.config["hooks"]["after_create"] == "project_hook"
      assert api.config["hooks"]["before_run"] == nil

      web = Enum.find(projects, &(&1.name == "web"))
      assert web.config["hooks"]["after_create"] == "global_hook"
      assert web.config["hooks"]["before_run"] == "global_before"
    end

    test "per-project prompt override" do
      config = %{
        "projects" => [
          %{
            "name" => "api",
            "tracker" => %{"kind" => "github", "repo" => "acme/api"},
            "prompt" => "API-specific prompt"
          },
          %{
            "name" => "web",
            "tracker" => %{"kind" => "github", "repo" => "acme/web"}
          }
        ]
      }

      projects = ProjectRegistry.resolve_projects(config, "global prompt")
      api = Enum.find(projects, &(&1.name == "api"))
      web = Enum.find(projects, &(&1.name == "web"))

      assert api.prompt_template == "API-specific prompt"
      assert web.prompt_template == "global prompt"
    end

    test "disabled project" do
      config = %{
        "projects" => [
          %{
            "name" => "api",
            "tracker" => %{"kind" => "github", "repo" => "acme/api"},
            "enabled" => false
          }
        ]
      }

      [project] = ProjectRegistry.resolve_projects(config, "prompt")
      assert project.enabled == false
    end
  end
end
