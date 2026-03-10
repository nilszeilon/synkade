defmodule Synkade.Settings.AgentTest do
  use ExUnit.Case, async: true

  alias Synkade.Settings.Agent

  describe "changeset/2" do
    test "valid with required fields" do
      changeset = Agent.changeset(%Agent{}, %{name: "my-agent"})
      assert changeset.valid?
    end

    test "requires name" do
      changeset = Agent.changeset(%Agent{}, %{})
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates kind inclusion" do
      changeset = Agent.changeset(%Agent{}, %{name: "a", kind: "gpt"})
      refute changeset.valid?
      assert %{kind: [_]} = errors_on(changeset)
    end

    test "accepts valid kinds" do
      for kind <- ["claude", "codex"] do
        changeset = Agent.changeset(%Agent{}, %{name: "a", kind: kind})
        assert changeset.valid?, "expected kind=#{kind} to be valid"
      end
    end

    test "validates auth_mode inclusion" do
      changeset = Agent.changeset(%Agent{}, %{name: "a", auth_mode: "basic"})
      refute changeset.valid?
      assert %{auth_mode: [_]} = errors_on(changeset)
    end

    test "validates max_turns is positive" do
      changeset = Agent.changeset(%Agent{}, %{name: "a", max_turns: 0})
      refute changeset.valid?
      assert %{max_turns: [_]} = errors_on(changeset)
    end

    test "accepts all fields" do
      changeset =
        Agent.changeset(%Agent{}, %{
          name: "full-agent",
          kind: "claude",
          auth_mode: "api_key",
          api_key: "sk-ant-test",
          model: "claude-sonnet-4-5-20250929",
          max_turns: 30,
          allowed_tools: ["Read", "Write"],
          system_prompt: "You are helpful."
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

    test "defaults allowed_tools to empty list" do
      agent = %Agent{}
      assert agent.allowed_tools == []
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
