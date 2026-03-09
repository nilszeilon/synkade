defmodule Synkade.Settings.ConfigAdapterTest do
  use ExUnit.Case, async: true

  alias Synkade.Settings.ConfigAdapter
  alias Synkade.Settings.{Setting, Project}

  describe "to_config/1 with PAT mode" do
    test "produces tracker config with api_key" do
      setting = %Setting{
        github_auth_mode: "pat",
        github_pat: "ghp_test123"
      }

      config = ConfigAdapter.to_config(setting)

      assert config["tracker"]["kind"] == "github"
      assert config["tracker"]["api_key"] == "ghp_test123"
      refute Map.has_key?(config["tracker"], "repo")
      refute Map.has_key?(config["tracker"], "endpoint")
      refute Map.has_key?(config["tracker"], "labels")
      refute Map.has_key?(config["tracker"], "app_id")
    end
  end

  describe "to_config/1 with App mode" do
    test "produces tracker config with app_id and private_key" do
      setting = %Setting{
        github_auth_mode: "app",
        github_app_id: "123456",
        github_private_key: "-----BEGIN RSA PRIVATE KEY-----\ntest",
        github_webhook_secret: "whsec_test"
      }

      config = ConfigAdapter.to_config(setting)

      assert config["tracker"]["kind"] == "github"
      assert config["tracker"]["app_id"] == "123456"
      assert config["tracker"]["private_key"] == "-----BEGIN RSA PRIVATE KEY-----\ntest"
      assert config["tracker"]["webhook_secret"] == "whsec_test"
      refute Map.has_key?(config["tracker"], "installation_id")
      refute Map.has_key?(config["tracker"], "endpoint")
      refute Map.has_key?(config["tracker"], "labels")
      refute Map.has_key?(config["tracker"], "api_key")
    end
  end

  describe "to_config/1 agent section" do
    test "produces agent config" do
      setting = %Setting{
        github_auth_mode: "pat",
        github_pat: "ghp_test",
        agent_kind: "claude",
        agent_api_key: "sk-ant-test",
        agent_model: "claude-sonnet-4-5-20250929",
        agent_max_turns: 30,
        agent_allowed_tools: ["Read", "Write"],
        agent_max_concurrent: 5
      }

      config = ConfigAdapter.to_config(setting)

      assert config["agent"]["kind"] == "claude"
      assert config["agent"]["api_key"] == "sk-ant-test"
      assert config["agent"]["model"] == "claude-sonnet-4-5-20250929"
      assert config["agent"]["max_turns"] == 30
      assert config["agent"]["allowed_tools"] == ["Read", "Write"]
      assert config["agent"]["max_concurrent_agents"] == 5
    end

    test "omits nil agent fields" do
      setting = %Setting{
        github_auth_mode: "pat",
        github_pat: "ghp_test"
      }

      config = ConfigAdapter.to_config(setting)

      refute Map.has_key?(config["agent"], "api_key")
      refute Map.has_key?(config["agent"], "model")
      refute Map.has_key?(config["agent"], "max_turns")
    end

    test "includes auth_mode and oauth_token for OAuth mode" do
      setting = %Setting{
        github_auth_mode: "pat",
        github_pat: "ghp_test",
        agent_kind: "claude",
        agent_auth_mode: "oauth",
        agent_oauth_token: "oauth-token-abc"
      }

      config = ConfigAdapter.to_config(setting)

      assert config["agent"]["auth_mode"] == "oauth"
      assert config["agent"]["oauth_token"] == "oauth-token-abc"
      refute Map.has_key?(config["agent"], "api_key")
    end

    test "includes auth_mode for api_key mode" do
      setting = %Setting{
        github_auth_mode: "pat",
        github_pat: "ghp_test",
        agent_auth_mode: "api_key",
        agent_api_key: "sk-ant-test"
      }

      config = ConfigAdapter.to_config(setting)

      assert config["agent"]["auth_mode"] == "api_key"
      assert config["agent"]["api_key"] == "sk-ant-test"
      refute Map.has_key?(config["agent"], "oauth_token")
    end
  end

  describe "to_config/1 execution section" do
    test "produces execution config" do
      setting = %Setting{
        github_auth_mode: "pat",
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
        github_auth_mode: "pat",
        github_pat: "ghp_test"
      }

      config = ConfigAdapter.to_config(setting)

      assert config["execution"]["backend"] == "local"
    end
  end

  describe "to_config/1 prompt template" do
    test "includes prompt_template when set" do
      setting = %Setting{
        github_auth_mode: "pat",
        github_pat: "ghp_test",
        prompt_template: "Fix {{ issue.title }}"
      }

      config = ConfigAdapter.to_config(setting)
      assert config["prompt_template"] == "Fix {{ issue.title }}"
    end

    test "omits prompt_template when nil" do
      setting = %Setting{
        github_auth_mode: "pat",
        github_pat: "ghp_test",
        prompt_template: nil
      }

      config = ConfigAdapter.to_config(setting)
      refute Map.has_key?(config, "prompt_template")
    end
  end

  describe "project_to_config/1" do
    test "produces config from project overrides" do
      project = %Project{
        name: "my-project",
        tracker_repo: "acme/api",
        agent_kind: "codex",
        agent_max_concurrent: 3
      }

      config = ConfigAdapter.project_to_config(project)

      assert config["tracker"]["repo"] == "acme/api"
      assert config["agent"]["kind"] == "codex"
      assert config["agent"]["max_concurrent_agents"] == 3
    end

    test "omits empty sections" do
      project = %Project{
        name: "minimal",
        tracker_repo: "acme/api"
      }

      config = ConfigAdapter.project_to_config(project)

      assert Map.has_key?(config, "tracker")
      refute Map.has_key?(config, "agent")
      refute Map.has_key?(config, "execution")
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

  describe "resolve_project_config/2" do
    test "merges global and project configs" do
      global = %Setting{
        github_auth_mode: "pat",
        github_pat: "ghp_global",
        agent_kind: "claude",
        agent_api_key: "sk-global",
        execution_backend: "local"
      }

      project = %Project{
        name: "api",
        tracker_repo: "acme/api",
        agent_max_concurrent: 3
      }

      config = ConfigAdapter.resolve_project_config(global, project)

      # Project overrides
      assert config["tracker"]["repo"] == "acme/api"
      assert config["agent"]["max_concurrent_agents"] == 3

      # Global preserved
      assert config["tracker"]["api_key"] == "ghp_global"
      assert config["agent"]["kind"] == "claude"
      assert config["agent"]["api_key"] == "sk-global"
      assert config["execution"]["backend"] == "local"
    end
  end
end
