defmodule Synkade.Workflow.ConfigTest do
  use ExUnit.Case, async: true

  alias Synkade.Workflow.Config

  describe "defaults" do
    test "returns default poll interval" do
      assert Config.poll_interval_ms(%{}) == 30_000
      assert Config.reconcile_interval_ms(%{}) == 30_000
    end

    test "returns default max concurrent agents" do
      assert Config.max_concurrent_agents(%{}) == 10
    end


    test "returns default agent kind" do
      assert Config.agent_kind(%{}) == "claude"
    end

    test "returns default tracker kind" do
      assert Config.tracker_kind(%{}) == "github"
    end

    test "returns kind-specific active_states for github" do
      config = %{"tracker" => %{"kind" => "github"}}
      assert Config.active_states(config) == ["open"]
    end

    test "returns kind-specific terminal_states for github" do
      config = %{"tracker" => %{"kind" => "github"}}
      assert Config.terminal_states(config) == ["closed"]
    end

    test "returns default agent command for claude" do
      assert Config.agent_command(%{}) == "claude"
    end

    test "returns default agent command for codex" do
      config = %{"agent" => %{"kind" => "codex"}}
      assert Config.agent_command(config) == "codex app-server"
    end
  end

  describe "overrides" do
    test "respects configured poll interval" do
      config = %{"polling" => %{"interval_ms" => 5000}}
      assert Config.poll_interval_ms(config) == 5000
      assert Config.reconcile_interval_ms(config) == 5000
    end

    test "respects string integer poll interval" do
      config = %{"polling" => %{"interval_ms" => "10000"}}
      assert Config.poll_interval_ms(config) == 10_000
      assert Config.reconcile_interval_ms(config) == 10_000
    end

    test "respects configured active_states" do
      config = %{"tracker" => %{"kind" => "github", "active_states" => ["open", "reopened"]}}
      assert Config.active_states(config) == ["open", "reopened"]
    end

    test "parses comma-separated active_states" do
      config = %{"tracker" => %{"kind" => "github", "active_states" => "open, reopened"}}
      assert Config.active_states(config) == ["open", "reopened"]
    end
  end

  describe "env resolution" do
    test "resolves $VAR from environment" do
      System.put_env("SYNKADE_TEST_TOKEN", "secret123")
      assert Config.resolve_env("$SYNKADE_TEST_TOKEN") == "secret123"
    after
      System.delete_env("SYNKADE_TEST_TOKEN")
    end

    test "returns nil for missing env var" do
      assert Config.resolve_env("$NONEXISTENT_VAR_ABC") == nil
    end

    test "returns nil for empty env var" do
      System.put_env("SYNKADE_EMPTY_VAR", "")
      assert Config.resolve_env("$SYNKADE_EMPTY_VAR") == nil
    after
      System.delete_env("SYNKADE_EMPTY_VAR")
    end

    test "passes through non-env values" do
      assert Config.resolve_env("regular_value") == "regular_value"
      assert Config.resolve_env(42) == 42
      assert Config.resolve_env(nil) == nil
    end
  end

  describe "path expansion" do
    test "expands ~ to home directory" do
      expanded = Config.expand_path("~/workspaces")
      assert expanded == Path.join(System.user_home!(), "workspaces")
    end

    test "passes through absolute paths" do
      assert Config.expand_path("/tmp/workspaces") == "/tmp/workspaces"
    end
  end

  describe "workspace_root/1" do
    test "returns system temp default when not configured" do
      root = Config.workspace_root(%{})
      assert root == Path.join(System.tmp_dir!(), "synkade_workspaces")
    end

    test "expands configured root" do
      config = %{"workspace" => %{"root" => "~/my_workspaces"}}
      root = Config.workspace_root(config)
      assert root == Path.join(System.user_home!(), "my_workspaces")
    end
  end

  describe "validate/1" do
    test "valid github config passes" do
      config = %{"tracker" => %{"kind" => "github", "repo" => "acme/api"}}
      assert :ok = Config.validate(config)
    end

    test "missing repo fails for github" do
      config = %{"tracker" => %{"kind" => "github"}}
      assert {:error, errors} = Config.validate(config)
      assert Enum.any?(errors, &String.contains?(&1, "tracker.repo"))
    end

    test "unsupported tracker kind fails" do
      config = %{"tracker" => %{"kind" => "jira", "repo" => "x"}}
      assert {:error, errors} = Config.validate(config)
      assert Enum.any?(errors, &String.contains?(&1, "tracker.kind"))
    end

    test "unsupported agent kind fails" do
      config = %{
        "tracker" => %{"kind" => "github", "repo" => "x"},
        "agent" => %{"kind" => "unknown"}
      }

      assert {:error, errors} = Config.validate(config)
      assert Enum.any?(errors, &String.contains?(&1, "agent.kind"))
    end

    test "sprites backend requires sprites_token" do
      config = %{
        "tracker" => %{"kind" => "github", "repo" => "acme/api"},
        "execution" => %{"backend" => "sprites"}
      }

      assert {:error, errors} = Config.validate(config)
      assert Enum.any?(errors, &String.contains?(&1, "sprites_token"))
    end

    test "sprites backend passes with token" do
      config = %{
        "tracker" => %{"kind" => "github", "repo" => "acme/api"},
        "execution" => %{"backend" => "sprites", "sprites_token" => "fly_token_123"}
      }

      assert :ok = Config.validate(config)
    end

    test "unsupported execution backend fails" do
      config = %{
        "tracker" => %{"kind" => "github", "repo" => "acme/api"},
        "execution" => %{"backend" => "docker"}
      }

      assert {:error, errors} = Config.validate(config)
      assert Enum.any?(errors, &String.contains?(&1, "execution.backend"))
    end
  end
end
