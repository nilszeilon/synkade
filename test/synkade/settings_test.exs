defmodule Synkade.SettingsTest do
  use Synkade.DataCase, async: true

  alias Synkade.Settings
  alias Synkade.Settings.Setting

  @valid_attrs %{
    "github_pat" => "ghp_test123"
  }

  describe "get_settings/0" do
    test "returns nil when no settings exist" do
      assert Settings.get_settings() == nil
    end

    test "returns setting when one exists" do
      {:ok, _setting} = Settings.save_settings(@valid_attrs)
      assert %Setting{} = Settings.get_settings()
    end
  end

  describe "save_settings/1" do
    test "creates settings with PAT" do
      assert {:ok, %Setting{} = setting} = Settings.save_settings(@valid_attrs)
      assert setting.github_pat == "ghp_test123"
    end

    test "upserts on second save" do
      {:ok, first} = Settings.save_settings(@valid_attrs)
      {:ok, second} = Settings.save_settings(Map.put(@valid_attrs, "github_pat", "ghp_updated"))
      assert first.id == second.id
      assert second.github_pat == "ghp_updated"
    end

    test "returns error changeset without required fields" do
      assert {:error, changeset} = Settings.save_settings(%{})
      assert errors_on(changeset).github_pat
    end

    test "validates agent_max_turns must be positive" do
      attrs = Map.put(@valid_attrs, "agent_max_turns", -1)
      assert {:error, changeset} = Settings.save_settings(attrs)
      assert errors_on(changeset).agent_max_turns
    end

    test "validates agent_max_concurrent must be positive" do
      attrs = Map.put(@valid_attrs, "agent_max_concurrent", 0)
      assert {:error, changeset} = Settings.save_settings(attrs)
      assert errors_on(changeset).agent_max_concurrent
    end

    test "validates agent_auth_mode inclusion" do
      attrs = Map.put(@valid_attrs, "agent_auth_mode", "invalid")
      assert {:error, changeset} = Settings.save_settings(attrs)
      assert errors_on(changeset).agent_auth_mode
    end

    test "saves settings with OAuth agent auth mode" do
      attrs = Map.merge(@valid_attrs, %{
        "agent_auth_mode" => "oauth",
        "agent_oauth_token" => "oauth-token-123"
      })

      assert {:ok, %Setting{} = setting} = Settings.save_settings(attrs)
      assert setting.agent_auth_mode == "oauth"
      assert setting.agent_oauth_token == "oauth-token-123"
    end

    test "requires agent_oauth_token when agent_auth_mode is oauth" do
      attrs = Map.put(@valid_attrs, "agent_auth_mode", "oauth")
      assert {:error, changeset} = Settings.save_settings(attrs)
      assert errors_on(changeset).agent_oauth_token
    end

    test "does not require agent_oauth_token when agent_auth_mode is api_key" do
      attrs = Map.put(@valid_attrs, "agent_auth_mode", "api_key")
      assert {:ok, %Setting{}} = Settings.save_settings(attrs)
    end
  end

  describe "change_settings/2" do
    test "returns changeset for empty setting" do
      changeset = Settings.change_settings(nil, %{})
      assert %Ecto.Changeset{} = changeset
    end

    test "returns changeset for existing setting" do
      {:ok, setting} = Settings.save_settings(@valid_attrs)
      changeset = Settings.change_settings(setting, %{"github_pat" => "ghp_updated"})
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "PubSub broadcast" do
    test "broadcasts on save" do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic())
      {:ok, setting} = Settings.save_settings(@valid_attrs)
      assert_receive {:settings_updated, ^setting}
    end
  end
end
