defmodule Synkade.SettingsTest do
  use Synkade.DataCase, async: true

  alias Synkade.Settings
  alias Synkade.Settings.Setting

  @valid_pat_attrs %{
    "github_auth_mode" => "pat",
    "github_pat" => "ghp_test123"
  }

  @valid_app_attrs %{
    "github_auth_mode" => "app",
    "github_app_id" => "123456",
    "github_private_key" => "-----BEGIN RSA PRIVATE KEY-----\ntest\n-----END RSA PRIVATE KEY-----"
  }

  describe "get_settings/0" do
    test "returns nil when no settings exist" do
      assert Settings.get_settings() == nil
    end

    test "returns setting when one exists" do
      {:ok, _setting} = Settings.save_settings(@valid_pat_attrs)
      assert %Setting{} = Settings.get_settings()
    end
  end

  describe "save_settings/1" do
    test "creates settings with PAT mode" do
      assert {:ok, %Setting{} = setting} = Settings.save_settings(@valid_pat_attrs)
      assert setting.github_auth_mode == "pat"
      assert setting.github_pat == "ghp_test123"
    end

    test "creates settings with App mode" do
      assert {:ok, %Setting{} = setting} = Settings.save_settings(@valid_app_attrs)
      assert setting.github_auth_mode == "app"
      assert setting.github_app_id == "123456"
    end

    test "upserts on second save" do
      {:ok, first} = Settings.save_settings(@valid_pat_attrs)
      {:ok, second} = Settings.save_settings(Map.put(@valid_pat_attrs, "github_pat", "ghp_updated"))
      assert first.id == second.id
      assert second.github_pat == "ghp_updated"
    end

    test "returns error changeset for PAT mode without required fields" do
      assert {:error, changeset} = Settings.save_settings(%{"github_auth_mode" => "pat"})
      assert errors_on(changeset).github_pat
    end

    test "returns error changeset for App mode without required fields" do
      assert {:error, changeset} = Settings.save_settings(%{"github_auth_mode" => "app"})
      assert errors_on(changeset).github_app_id
      assert errors_on(changeset).github_private_key
    end

    test "validates agent_max_turns must be positive" do
      attrs = Map.put(@valid_pat_attrs, "agent_max_turns", -1)
      assert {:error, changeset} = Settings.save_settings(attrs)
      assert errors_on(changeset).agent_max_turns
    end

    test "validates agent_max_concurrent must be positive" do
      attrs = Map.put(@valid_pat_attrs, "agent_max_concurrent", 0)
      assert {:error, changeset} = Settings.save_settings(attrs)
      assert errors_on(changeset).agent_max_concurrent
    end

    test "validates github_auth_mode inclusion" do
      attrs = Map.put(@valid_pat_attrs, "github_auth_mode", "invalid")
      assert {:error, changeset} = Settings.save_settings(attrs)
      assert errors_on(changeset).github_auth_mode
    end

    test "validates agent_auth_mode inclusion" do
      attrs = Map.put(@valid_pat_attrs, "agent_auth_mode", "invalid")
      assert {:error, changeset} = Settings.save_settings(attrs)
      assert errors_on(changeset).agent_auth_mode
    end

    test "saves settings with OAuth agent auth mode" do
      attrs = Map.merge(@valid_pat_attrs, %{
        "agent_auth_mode" => "oauth",
        "agent_oauth_token" => "oauth-token-123"
      })

      assert {:ok, %Setting{} = setting} = Settings.save_settings(attrs)
      assert setting.agent_auth_mode == "oauth"
      assert setting.agent_oauth_token == "oauth-token-123"
    end

    test "requires agent_oauth_token when agent_auth_mode is oauth" do
      attrs = Map.put(@valid_pat_attrs, "agent_auth_mode", "oauth")
      assert {:error, changeset} = Settings.save_settings(attrs)
      assert errors_on(changeset).agent_oauth_token
    end

    test "does not require agent_oauth_token when agent_auth_mode is api_key" do
      attrs = Map.put(@valid_pat_attrs, "agent_auth_mode", "api_key")
      assert {:ok, %Setting{}} = Settings.save_settings(attrs)
    end
  end

  describe "change_settings/2" do
    test "returns changeset for empty setting" do
      changeset = Settings.change_settings(nil, %{})
      assert %Ecto.Changeset{} = changeset
    end

    test "returns changeset for existing setting" do
      {:ok, setting} = Settings.save_settings(@valid_pat_attrs)
      changeset = Settings.change_settings(setting, %{"github_pat" => "ghp_updated"})
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "PubSub broadcast" do
    test "broadcasts on save" do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic())
      {:ok, setting} = Settings.save_settings(@valid_pat_attrs)
      assert_receive {:settings_updated, ^setting}
    end
  end
end
