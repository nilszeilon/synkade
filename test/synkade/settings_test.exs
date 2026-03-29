defmodule Synkade.SettingsTest do
  use Synkade.DataCase

  import Synkade.AccountsFixtures

  alias Synkade.Settings
  alias Synkade.Settings.{Setting, Agent}

  @valid_attrs %{
    "github_pat" => "ghp_test123"
  }

  setup do
    scope = user_scope_fixture()
    %{scope: scope}
  end

  describe "get_settings/1" do
    test "returns nil when no settings exist", %{scope: scope} do
      assert Settings.get_settings(scope) == nil
    end

    test "returns setting when one exists", %{scope: scope} do
      {:ok, _setting} = Settings.save_settings(scope, @valid_attrs)
      assert %Setting{} = Settings.get_settings(scope)
    end
  end

  describe "save_settings/2" do
    test "creates settings with PAT", %{scope: scope} do
      assert {:ok, %Setting{} = setting} = Settings.save_settings(scope, @valid_attrs)
      assert setting.github_pat == "ghp_test123"
    end

    test "upserts on second save", %{scope: scope} do
      {:ok, first} = Settings.save_settings(scope, @valid_attrs)
      {:ok, second} = Settings.save_settings(scope, Map.put(@valid_attrs, "github_pat", "ghp_updated"))
      assert first.id == second.id
      assert second.github_pat == "ghp_updated"
    end

    test "returns error changeset without required fields", %{scope: scope} do
      assert {:error, changeset} = Settings.save_settings(scope, %{})
      assert errors_on(changeset).github_pat
    end
  end

  describe "change_settings/3" do
    test "returns changeset for empty setting", %{scope: scope} do
      changeset = Settings.change_settings(scope, nil, %{})
      assert %Ecto.Changeset{} = changeset
    end

    test "returns changeset for existing setting", %{scope: scope} do
      {:ok, setting} = Settings.save_settings(scope, @valid_attrs)
      changeset = Settings.change_settings(scope, setting, %{"github_pat" => "ghp_updated"})
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "PubSub broadcast" do
    test "broadcasts on save", %{scope: scope} do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic(scope))
      {:ok, setting} = Settings.save_settings(scope, @valid_attrs)
      assert_receive {:settings_updated, ^setting}
    end
  end

  # --- Agent CRUD ---

  describe "list_agents/1" do
    test "returns empty list when no agents", %{scope: scope} do
      assert Settings.list_agents(scope) == []
    end

    test "returns agents sorted by name", %{scope: scope} do
      # Use pull kinds so we can set custom names
      {:ok, _} = Settings.create_agent(scope, %{name: "beta", kind: "hermes"})
      {:ok, _} = Settings.create_agent(scope, %{name: "alpha", kind: "openclaw"})
      agents = Settings.list_agents(scope)
      assert [%Agent{name: "alpha"}, %Agent{name: "beta"}] = agents
    end
  end

  describe "get_agent!/1" do
    test "returns agent by ID", %{scope: scope} do
      {:ok, agent} = Settings.create_agent(scope, %{name: "test-agent", kind: "hermes"})
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

  describe "get_agent_by_name/2" do
    test "returns agent by name", %{scope: scope} do
      {:ok, _} = Settings.create_agent(scope, %{name: "named-agent", kind: "hermes"})
      assert %Agent{name: "named-agent"} = Settings.get_agent_by_name(scope, "named-agent")
    end

    test "returns ephemeral agent by kind name", %{scope: scope} do
      {:ok, _} = Settings.create_agent(scope, %{kind: "claude"})
      assert %Agent{name: "claude"} = Settings.get_agent_by_name(scope, "claude")
    end

    test "returns nil for missing name", %{scope: scope} do
      assert Settings.get_agent_by_name(scope, "nonexistent") == nil
    end
  end

  describe "create_agent/2" do
    test "creates ephemeral agent with auto-name and token", %{scope: scope} do
      assert {:ok, %Agent{} = agent} =
               Settings.create_agent(scope, %{
                 kind: "claude",
                 api_key: "sk-ant-test"
               })

      assert agent.name == "claude"
      assert agent.kind == "claude"
      assert agent.api_key == "sk-ant-test"
      assert agent.api_token_hash != nil
      assert agent.api_token != nil
      assert String.starts_with?(agent.api_token, "synkade_")
    end

    test "creates pull agent with custom name and token", %{scope: scope} do
      assert {:ok, %Agent{} = agent} =
               Settings.create_agent(scope, %{
                 name: "my-hermes",
                 kind: "hermes"
               })

      assert agent.name == "my-hermes"
      assert agent.kind == "hermes"
      assert agent.api_token != nil
    end

    test "auto-generated token is verifiable", %{scope: scope} do
      {:ok, agent} = Settings.create_agent(scope, %{kind: "claude"})
      assert {:ok, found} = Settings.verify_agent_token(agent.api_token)
      assert found.id == agent.id
    end

    test "returns error for duplicate name", %{scope: scope} do
      {:ok, _} = Settings.create_agent(scope, %{name: "duplicate", kind: "hermes"})
      assert {:error, changeset} = Settings.create_agent(scope, %{name: "duplicate", kind: "openclaw"})
      errors = errors_on(changeset)
      assert errors[:name] || errors[:user_id]
    end

    test "broadcasts agents_updated", %{scope: scope} do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic(scope))
      {:ok, _} = Settings.create_agent(scope, %{kind: "claude"})
      assert_receive {:agents_updated}
    end
  end

  describe "upsert_ephemeral_agent/2" do
    test "creates when none exists", %{scope: scope} do
      assert {:ok, %Agent{} = agent} =
               Settings.upsert_ephemeral_agent(scope, %{"kind" => "claude", "api_key" => "sk-test"})

      assert agent.name == "claude"
      assert agent.api_key == "sk-test"
    end

    test "updates when one already exists", %{scope: scope} do
      {:ok, first} = Settings.create_agent(scope, %{kind: "claude", api_key: "sk-old"})
      {:ok, updated} = Settings.upsert_ephemeral_agent(scope, %{"kind" => "claude", "api_key" => "sk-new"})
      assert updated.id == first.id
      assert updated.api_key == "sk-new"
    end
  end

  describe "update_agent/3" do
    test "updates pull agent fields", %{scope: scope} do
      {:ok, agent} = Settings.create_agent(scope, %{name: "original", kind: "hermes"})
      {:ok, updated} = Settings.update_agent(scope, agent, %{name: "renamed"})
      assert updated.name == "renamed"
    end

    test "ephemeral agent name stays as kind on update", %{scope: scope} do
      {:ok, agent} = Settings.create_agent(scope, %{kind: "opencode"})
      {:ok, updated} = Settings.update_agent(scope, agent, %{api_key: "sk-new"})
      assert updated.name == "opencode"
    end

    test "broadcasts agents_updated", %{scope: scope} do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic(scope))
      {:ok, agent} = Settings.create_agent(scope, %{name: "update-broadcast", kind: "hermes"})
      # Drain the create broadcast
      assert_receive {:agents_updated}

      {:ok, _} = Settings.update_agent(scope, agent, %{name: "updated-broadcast"})
      assert_receive {:agents_updated}
    end
  end

  describe "delete_agent/2" do
    test "deletes agent", %{scope: scope} do
      {:ok, agent} = Settings.create_agent(scope, %{name: "to-delete", kind: "hermes"})
      {:ok, _} = Settings.delete_agent(scope, agent)
      assert Settings.get_agent_by_name(scope, "to-delete") == nil
    end

    test "broadcasts agents_updated", %{scope: scope} do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Settings.pubsub_topic(scope))
      {:ok, agent} = Settings.create_agent(scope, %{name: "delete-broadcast", kind: "hermes"})
      assert_receive {:agents_updated}

      {:ok, _} = Settings.delete_agent(scope, agent)
      assert_receive {:agents_updated}
    end
  end

  # --- Agent API Tokens ---

  describe "generate_agent_token/1" do
    test "returns a plaintext token with synkade_ prefix", %{scope: scope} do
      {:ok, agent} = Settings.create_agent(scope, %{kind: "claude"})
      {:ok, token} = Settings.generate_agent_token(agent)
      assert String.starts_with?(token, "synkade_")
    end

    test "stores hash on agent record", %{scope: scope} do
      {:ok, agent} = Settings.create_agent(scope, %{name: "token-hash-agent", kind: "hermes"})
      {:ok, _token} = Settings.generate_agent_token(agent)
      updated = Settings.get_agent!(agent.id)
      assert updated.api_token_hash != nil
    end
  end

  describe "verify_agent_token/1" do
    test "verifies a valid token", %{scope: scope} do
      {:ok, agent} = Settings.create_agent(scope, %{kind: "claude"})
      {:ok, token} = Settings.generate_agent_token(agent)
      assert {:ok, found} = Settings.verify_agent_token(token)
      assert found.id == agent.id
    end

    test "rejects an invalid token" do
      assert :error = Settings.verify_agent_token("synkade_invalid")
    end

    test "rejects after token regeneration", %{scope: scope} do
      {:ok, agent} = Settings.create_agent(scope, %{name: "regen-agent", kind: "hermes"})
      {:ok, old_token} = Settings.generate_agent_token(agent)
      agent = Settings.get_agent!(agent.id)
      {:ok, new_token} = Settings.generate_agent_token(agent)
      assert :error = Settings.verify_agent_token(old_token)
      assert {:ok, _} = Settings.verify_agent_token(new_token)
    end
  end

  describe "revoke_agent_token/2" do
    test "clears the token hash", %{scope: scope} do
      {:ok, agent} = Settings.create_agent(scope, %{kind: "claude"})
      {:ok, token} = Settings.generate_agent_token(agent)
      agent = Settings.get_agent!(agent.id)
      {:ok, revoked} = Settings.revoke_agent_token(scope, agent)
      assert revoked.api_token_hash == nil
      assert :error = Settings.verify_agent_token(token)
    end
  end
end
