defmodule Synkade.Settings.ConfigAdapterTest do
  use ExUnit.Case, async: true

  alias Synkade.Settings.ConfigAdapter
  alias Synkade.Settings.Setting

  describe "to_config/1 with PAT mode" do
    test "produces tracker config with api_key and repo" do
      setting = %Setting{
        github_auth_mode: "pat",
        github_pat: "ghp_test123",
        github_repo: "owner/repo",
        github_endpoint: "https://github.example.com/api/v3",
        tracker_labels: ["synkade"]
      }

      config = ConfigAdapter.to_config(setting)

      assert config["tracker"]["kind"] == "github"
      assert config["tracker"]["api_key"] == "ghp_test123"
      assert config["tracker"]["repo"] == "owner/repo"
      assert config["tracker"]["endpoint"] == "https://github.example.com/api/v3"
      assert config["tracker"]["labels"] == ["synkade"]
      refute Map.has_key?(config["tracker"], "app_id")
    end
  end

  describe "to_config/1 with App mode" do
    test "produces tracker config with app_id and private_key" do
      setting = %Setting{
        github_auth_mode: "app",
        github_app_id: "123456",
        github_private_key: "-----BEGIN RSA PRIVATE KEY-----\ntest",
        github_webhook_secret: "whsec_test",
        github_installation_id: "789"
      }

      config = ConfigAdapter.to_config(setting)

      assert config["tracker"]["kind"] == "github"
      assert config["tracker"]["app_id"] == "123456"
      assert config["tracker"]["private_key"] == "-----BEGIN RSA PRIVATE KEY-----\ntest"
      assert config["tracker"]["webhook_secret"] == "whsec_test"
      assert config["tracker"]["installation_id"] == "789"
      refute Map.has_key?(config["tracker"], "api_key")
    end
  end

  describe "to_config/1 agent section" do
    test "produces agent config" do
      setting = %Setting{
        github_auth_mode: "pat",
        github_pat: "ghp_test",
        github_repo: "o/r",
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
        github_pat: "ghp_test",
        github_repo: "o/r"
      }

      config = ConfigAdapter.to_config(setting)

      refute Map.has_key?(config["agent"], "api_key")
      refute Map.has_key?(config["agent"], "model")
      refute Map.has_key?(config["agent"], "max_turns")
    end
  end

  describe "to_config/1 prompt template" do
    test "includes prompt_template when set" do
      setting = %Setting{
        github_auth_mode: "pat",
        github_pat: "ghp_test",
        github_repo: "o/r",
        prompt_template: "Fix {{ issue.title }}"
      }

      config = ConfigAdapter.to_config(setting)
      assert config["prompt_template"] == "Fix {{ issue.title }}"
    end

    test "omits prompt_template when nil" do
      setting = %Setting{
        github_auth_mode: "pat",
        github_pat: "ghp_test",
        github_repo: "o/r",
        prompt_template: nil
      }

      config = ConfigAdapter.to_config(setting)
      refute Map.has_key?(config, "prompt_template")
    end
  end

  describe "merge_into/2" do
    test "DB settings override file config" do
      file_config = %{
        "tracker" => %{
          "kind" => "github",
          "api_key" => "old_key",
          "repo" => "old/repo"
        },
        "agent" => %{
          "kind" => "claude",
          "model" => "old-model"
        },
        "polling" => %{
          "interval_ms" => 60_000
        }
      }

      setting = %Setting{
        github_auth_mode: "pat",
        github_pat: "new_key",
        github_repo: "new/repo",
        agent_model: "new-model"
      }

      merged = ConfigAdapter.merge_into(file_config, setting)

      # DB wins
      assert merged["tracker"]["api_key"] == "new_key"
      assert merged["tracker"]["repo"] == "new/repo"
      assert merged["agent"]["model"] == "new-model"

      # File-only keys preserved
      assert merged["polling"]["interval_ms"] == 60_000
    end

    test "preserves file config sections not in DB" do
      file_config = %{
        "tracker" => %{"kind" => "github"},
        "workspace" => %{"root" => "/tmp/workspaces"}
      }

      setting = %Setting{
        github_auth_mode: "pat",
        github_pat: "test",
        github_repo: "o/r"
      }

      merged = ConfigAdapter.merge_into(file_config, setting)
      assert merged["workspace"]["root"] == "/tmp/workspaces"
    end
  end
end
