defmodule Synkade.SettingsTest do
  use Synkade.DataCase

  alias Synkade.Settings
  alias Synkade.Settings.{Setting, Agent}

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

  # --- Agent CRUD ---

  describe "list_agents/0" do
    test "returns empty list when no agents" do
      assert Settings.list_agents() == []
    end

    test "returns agents sorted by name" do
      {:ok, _} = Settings.create_agent(%{name: "beta"})
      {:ok, _} = Settings.create_agent(%{name: "alpha"})
      agents = Settings.list_agents()
      assert [%Agent{name: "alpha"}, %Agent{name: "beta"}] = agents
    end
  end

  describe "get_agent!/1" do
    test "returns agent by ID" do
      {:ok, agent} = Settings.create_agent(%{name: "test-agent"})
      fetched = Settings.get_agent!(agent.id)
      assert fetched.id == agent.id
      assert fetched.name == "test-agent"
    end

    test "raises for missing ID" do
      assert_raise Ecto.NoResultsError, fn ->
        Settings.get_agent!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_agent_by_name/1" do
    test "returns agent by name" do
      {:ok, _} = Settings.create_agent(%{name: "named-agent"})
      assert %Agent{name: "named-agent"} = Settings.get_agent_by_name("named-agent")
    end

    test "returns nil for missing name" do
      assert Settings.get_agent_by_name("nonexistent") == nil
    end
  end

  describe "create_agent/1" do
    test "creates agent with valid attrs and auto-generated token" do
      assert {:ok, %Agent{} = agent} =
               Settings.create_agent(%{
                 name: "my-agent",
                 kind: "claude",
                 api_key: "sk-ant-test",
                 model: "claude-sonnet-4-5-20250929"
               })

      assert agent.name == "my-agent"
      assert agent.kind == "claude"
      assert agent.api_key == "sk-ant-test"
      assert agent.api_token_hash != nil
      assert agent.api_token != nil
      assert String.starts_with?(agent.api_token, "synkade_")
    end

    test "auto-generated token is verifiable" do
      {:ok, agent} = Settings.create_agent(%{name: "verify-auto"})
      assert {:ok, found} = Settings.verify_agent_token(agent.api_token)
      assert found.id == agent.id
    end

    test "returns error for duplicate name" do
      {:ok, _} = Settings.create_agent(%{name: "duplicate"})
      assert {:error, changeset} = Settings.create_agent(%{name: "duplicate"})
      assert errors_on(changeset).name
    end

    test "broadcasts agents_updated" do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic())
      {:ok, _} = Settings.create_agent(%{name: "broadcast-test"})
      assert_receive {:agents_updated}
    end
  end

  describe "update_agent/2" do
    test "updates agent fields" do
      {:ok, agent} = Settings.create_agent(%{name: "original"})
      {:ok, updated} = Settings.update_agent(agent, %{name: "renamed", model: "new-model"})
      assert updated.name == "renamed"
      assert updated.model == "new-model"
    end

    test "broadcasts agents_updated" do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic())
      {:ok, agent} = Settings.create_agent(%{name: "update-broadcast"})
      # Drain the create broadcast
      assert_receive {:agents_updated}

      {:ok, _} = Settings.update_agent(agent, %{model: "x"})
      assert_receive {:agents_updated}
    end
  end

  describe "delete_agent/1" do
    test "deletes agent" do
      {:ok, agent} = Settings.create_agent(%{name: "to-delete"})
      {:ok, _} = Settings.delete_agent(agent)
      assert Settings.get_agent_by_name("to-delete") == nil
    end

    test "broadcasts agents_updated" do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic())
      {:ok, agent} = Settings.create_agent(%{name: "delete-broadcast"})
      assert_receive {:agents_updated}

      {:ok, _} = Settings.delete_agent(agent)
      assert_receive {:agents_updated}
    end
  end

  # --- Agent API Tokens ---

  describe "generate_agent_token/1" do
    test "returns a plaintext token with synkade_ prefix" do
      {:ok, agent} = Settings.create_agent(%{name: "token-agent"})
      {:ok, token} = Settings.generate_agent_token(agent)
      assert String.starts_with?(token, "synkade_")
    end

    test "stores hash on agent record" do
      {:ok, agent} = Settings.create_agent(%{name: "token-hash-agent"})
      {:ok, _token} = Settings.generate_agent_token(agent)
      updated = Settings.get_agent!(agent.id)
      assert updated.api_token_hash != nil
    end
  end

  describe "verify_agent_token/1" do
    test "verifies a valid token" do
      {:ok, agent} = Settings.create_agent(%{name: "verify-agent"})
      {:ok, token} = Settings.generate_agent_token(agent)
      assert {:ok, found} = Settings.verify_agent_token(token)
      assert found.id == agent.id
    end

    test "rejects an invalid token" do
      assert :error = Settings.verify_agent_token("synkade_invalid")
    end

    test "rejects after token regeneration" do
      {:ok, agent} = Settings.create_agent(%{name: "regen-agent"})
      {:ok, old_token} = Settings.generate_agent_token(agent)
      agent = Settings.get_agent!(agent.id)
      {:ok, new_token} = Settings.generate_agent_token(agent)
      assert :error = Settings.verify_agent_token(old_token)
      assert {:ok, _} = Settings.verify_agent_token(new_token)
    end
  end

  describe "revoke_agent_token/1" do
    test "clears the token hash" do
      {:ok, agent} = Settings.create_agent(%{name: "revoke-agent"})
      {:ok, token} = Settings.generate_agent_token(agent)
      agent = Settings.get_agent!(agent.id)
      {:ok, revoked} = Settings.revoke_agent_token(agent)
      assert revoked.api_token_hash == nil
      assert :error = Settings.verify_agent_token(token)
    end
  end
end
