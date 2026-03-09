defmodule Synkade.Settings.ProjectTest do
  use Synkade.DataCase, async: true

  alias Synkade.Settings.Project

  describe "changeset/2" do
    test "valid with just a name" do
      changeset = Project.changeset(%Project{}, %{name: "my-project"})
      assert changeset.valid?
    end

    test "requires name" do
      changeset = Project.changeset(%Project{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "validates tracker_kind inclusion" do
      changeset = Project.changeset(%Project{}, %{name: "p", tracker_kind: "jira"})
      refute changeset.valid?
      assert errors_on(changeset).tracker_kind
    end

    test "validates agent_kind inclusion" do
      changeset = Project.changeset(%Project{}, %{name: "p", agent_kind: "gpt"})
      refute changeset.valid?
      assert errors_on(changeset).agent_kind
    end

    test "validates agent_auth_mode inclusion" do
      changeset = Project.changeset(%Project{}, %{name: "p", agent_auth_mode: "magic"})
      refute changeset.valid?
      assert errors_on(changeset).agent_auth_mode
    end

    test "validates execution_backend inclusion" do
      changeset = Project.changeset(%Project{}, %{name: "p", execution_backend: "docker"})
      refute changeset.valid?
      assert errors_on(changeset).execution_backend
    end

    test "validates agent_max_turns > 0" do
      changeset = Project.changeset(%Project{}, %{name: "p", agent_max_turns: 0})
      refute changeset.valid?
      assert errors_on(changeset).agent_max_turns
    end

    test "accepts valid enum values" do
      changeset =
        Project.changeset(%Project{}, %{
          name: "my-project",
          tracker_kind: "github",
          agent_kind: "claude",
          agent_auth_mode: "api_key",
          execution_backend: "local"
        })

      assert changeset.valid?
    end

    test "defaults enabled to true" do
      changeset = Project.changeset(%Project{}, %{name: "p"})
      assert Ecto.Changeset.get_field(changeset, :enabled) == true
    end
  end
end
