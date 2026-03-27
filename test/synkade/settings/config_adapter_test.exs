defmodule Synkade.Settings.ConfigAdapterTest do
  use ExUnit.Case, async: true

  alias Synkade.Settings.ConfigAdapter
  alias Synkade.Settings.{Setting, Project, Agent}

  describe "to_config/1 tracker section" do
    test "produces tracker config with api_key" do
      setting = %Setting{
        github_pat: "ghp_test123"
      }

      config = ConfigAdapter.to_config(setting)

      assert config["tracker"]["kind"] == "github"
      assert config["tracker"]["api_key"] == "ghp_test123"
    end

    test "includes webhook_secret when set" do
      setting = %Setting{
        github_pat: "ghp_test123",
        github_webhook_secret: "whsec_test"
      }

      config = ConfigAdapter.to_config(setting)

      assert config["tracker"]["webhook_secret"] == "whsec_test"
    end
  end

  describe "to_config/1 no agent section" do
    test "does not include agent section" do
      setting = %Setting{github_pat: "ghp_test"}
      config = ConfigAdapter.to_config(setting)
      refute Map.has_key?(config, "agent")
    end
  end

  describe "to_config/1 execution section" do
    test "produces execution config" do
      setting = %Setting{
        github_pat: "ghp_test",
        execution_backend: "sprites",
        execution_sprites_token: "fly_token_123",
        execution_sprites_org: "my-org"
      }

      config = ConfigAdapter.to_config(setting)

      assert config["execution"]["backend"] == "sprites"
      assert config["execution"]["sprites_token"] == "fly_token_123"
      assert config["execution"]["sprites_org"] == "my-org"
    end

    test "defaults to local backend" do
      setting = %Setting{
        github_pat: "ghp_test"
      }

      config = ConfigAdapter.to_config(setting)

      assert config["execution"]["backend"] == "local"
    end
  end

  describe "agent_to_config/1" do
    test "produces agent config from Agent struct" do
      agent = %Agent{
        kind: "claude",
        auth_mode: "api_key",
        api_key: "sk-ant-test",
        model: "claude-sonnet-4-5-20250929"
      }

      config = ConfigAdapter.agent_to_config(agent)

      assert config["kind"] == "claude"
      assert config["auth_mode"] == "api_key"
      assert config["api_key"] == "sk-ant-test"
      assert config["model"] == "claude-sonnet-4-5-20250929"
    end

    test "omits nil agent fields" do
      agent = %Agent{kind: "claude", auth_mode: "api_key"}

      config = ConfigAdapter.agent_to_config(agent)

      refute Map.has_key?(config, "api_key")
      refute Map.has_key?(config, "model")
    end

    test "includes oauth_token for OAuth mode" do
      agent = %Agent{
        kind: "claude",
        auth_mode: "oauth",
        oauth_token: "oauth-token-abc"
      }

      config = ConfigAdapter.agent_to_config(agent)

      assert config["auth_mode"] == "oauth"
      assert config["oauth_token"] == "oauth-token-abc"
      refute Map.has_key?(config, "api_key")
    end
  end

  describe "project_to_config/1" do
    test "produces config from project overrides" do
      project = %Project{
        name: "my-project",
        tracker_repo: "acme/api"
      }

      config = ConfigAdapter.project_to_config(project)

      assert config["tracker"]["repo"] == "acme/api"
    end

    test "omits empty sections" do
      project = %Project{
        name: "minimal"
      }

      config = ConfigAdapter.project_to_config(project)

      refute Map.has_key?(config, "tracker")
    end

    test "includes prompt_template when set" do
      project = %Project{
        name: "my-project",
        prompt_template: "Custom prompt"
      }

      config = ConfigAdapter.project_to_config(project)
      assert config["prompt_template"] == "Custom prompt"
    end
  end

  describe "resolve_project_config/3" do
    test "merges global, project, and agent configs" do
      global = %Setting{
        github_pat: "ghp_global",
        execution_backend: "local"
      }

      project = %Project{
        name: "api",
        tracker_repo: "acme/api"
      }

      agent = %Agent{
        kind: "claude",
        auth_mode: "api_key",
        api_key: "sk-global",
        model: "claude-sonnet-4-5-20250929"
      }

      config = ConfigAdapter.resolve_project_config(global, project, agent)

      # Project overrides
      assert config["tracker"]["repo"] == "acme/api"

      # Global preserved
      assert config["tracker"]["api_key"] == "ghp_global"
      assert config["execution"]["backend"] == "local"

      # Agent config
      assert config["agent"]["kind"] == "claude"
      assert config["agent"]["api_key"] == "sk-global"
      assert config["agent"]["model"] == "claude-sonnet-4-5-20250929"
    end

    test "agent config is placed under 'agent' key" do
      global = %Setting{github_pat: "ghp_test"}
      project = %Project{name: "test"}
      agent = %Agent{kind: "codex", auth_mode: "api_key", api_key: "sk-codex"}

      config = ConfigAdapter.resolve_project_config(global, project, agent)

      assert config["agent"]["kind"] == "codex"
      assert config["agent"]["api_key"] == "sk-codex"
    end

    test "includes user_id from project" do
      global = %Setting{github_pat: "ghp_test"}
      project = %Project{name: "test", user_id: "user-abc-123"}
      agent = %Agent{kind: "claude", auth_mode: "api_key"}

      config = ConfigAdapter.resolve_project_config(global, project, agent)

      assert config["user_id"] == "user-abc-123"
    end
  end
end
