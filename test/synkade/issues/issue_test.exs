defmodule Synkade.Issues.IssueTest do
  use Synkade.DataCase, async: true

  alias Synkade.Issues.Issue

  defp create_project(_) do
    {:ok, project} = Synkade.Settings.create_project(%{name: "test-project"})
    %{project: project}
  end

  setup :create_project

  describe "changeset/2" do
    test "valid with required fields", %{project: project} do
      changeset = Issue.changeset(%Issue{}, %{title: "Fix bug", project_id: project.id})
      assert changeset.valid?
    end

    test "invalid without title", %{project: project} do
      changeset = Issue.changeset(%Issue{}, %{project_id: project.id})
      refute changeset.valid?
      assert errors_on(changeset).title
    end

    test "invalid without project_id" do
      changeset = Issue.changeset(%Issue{}, %{title: "Fix bug"})
      refute changeset.valid?
      assert errors_on(changeset).project_id
    end

    test "validates state inclusion" do
      changeset =
        Issue.changeset(%Issue{}, %{
          title: "X",
          project_id: Ecto.UUID.generate(),
          state: "invalid"
        })

      refute changeset.valid?
      assert errors_on(changeset).state
    end

    test "accepts all valid states" do
      for state <- ~w(backlog queued in_progress awaiting_review done cancelled) do
        changeset =
          Issue.changeset(%Issue{}, %{title: "X", project_id: Ecto.UUID.generate(), state: state})

        assert changeset.valid?, "Expected state #{state} to be valid"
      end
    end

    test "defaults", %{project: project} do
      changeset = Issue.changeset(%Issue{}, %{title: "Test", project_id: project.id})
      assert get_field(changeset, :state) == "backlog"
      assert get_field(changeset, :depth) == 0
      assert get_field(changeset, :position) == 0
      assert get_field(changeset, :priority) == 0
    end
  end
end
