defmodule Synkade.Settings.AgentTest do
  use ExUnit.Case, async: true

  alias Synkade.Settings.Agent

  describe "changeset/2" do
    test "valid with required fields" do
      changeset = Agent.changeset(%Agent{}, %{kind: "hermes"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :name) == "hermes"
    end

    test "auto-sets name to kind for all agents" do
      changeset = Agent.changeset(%Agent{}, %{kind: "claude"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :name) == "claude"
    end

    test "validates kind inclusion" do
      changeset = Agent.changeset(%Agent{}, %{name: "a", kind: "gpt"})
      refute changeset.valid?
      assert %{kind: [_]} = errors_on(changeset)
    end

    test "accepts valid kinds" do
      for kind <- ~w(claude codex opencode hermes openclaw) do
        changeset = Agent.changeset(%Agent{}, %{kind: kind})
        assert changeset.valid?, "expected kind=#{kind} to be valid"
      end
    end

    test "validates auth_mode inclusion" do
      changeset = Agent.changeset(%Agent{}, %{kind: "hermes", auth_mode: "basic"})
      refute changeset.valid?
      assert %{auth_mode: [_]} = errors_on(changeset)
    end

    test "accepts all fields" do
      changeset =
        Agent.changeset(%Agent{}, %{
          kind: "hermes",
          auth_mode: "api_key",
          api_key: "sk-ant-test"
        })

      assert changeset.valid?
    end

    test "defaults kind to claude" do
      agent = %Agent{}
      assert agent.kind == "claude"
    end

    test "defaults auth_mode to api_key" do
      agent = %Agent{}
      assert agent.auth_mode == "api_key"
    end
  end

  describe "kinds/0" do
    test "returns all supported kinds" do
      kinds = Agent.kinds()
      assert "claude" in kinds
      assert "codex" in kinds
      assert "opencode" in kinds
      assert "hermes" in kinds
      assert "openclaw" in kinds
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
