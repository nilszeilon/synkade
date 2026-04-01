defmodule Synkade.Issues.IssueTest do
  use Synkade.DataCase

  import Synkade.AccountsFixtures

  alias Synkade.Issues.Issue

  defp create_project(_) do
    scope = user_scope_fixture()
    {:ok, project} = Synkade.Settings.create_project(scope, %{name: "test-project"})
    %{project: project}
  end

  setup :create_project

  describe "changeset/2" do
    test "valid with required fields", %{project: project} do
      changeset = Issue.changeset(%Issue{}, %{project_id: project.id})
      assert changeset.valid?
    end

    test "valid with body", %{project: project} do
      changeset = Issue.changeset(%Issue{}, %{body: "# Fix bug", project_id: project.id})
      assert changeset.valid?
    end

    test "invalid without project_id" do
      changeset = Issue.changeset(%Issue{}, %{body: "# Fix bug"})
      refute changeset.valid?
      assert errors_on(changeset).project_id
    end

    test "validates state inclusion" do
      changeset =
        Issue.changeset(%Issue{}, %{
          project_id: Ecto.UUID.generate(),
          state: "invalid"
        })

      refute changeset.valid?
      assert errors_on(changeset).state
    end

    test "accepts all valid states" do
      for state <- ~w(backlog worked_on done) do
        changeset =
          Issue.changeset(%Issue{}, %{project_id: Ecto.UUID.generate(), state: state})

        assert changeset.valid?, "Expected state #{state} to be valid"
      end
    end

    test "defaults", %{project: project} do
      changeset = Issue.changeset(%Issue{}, %{project_id: project.id})
      assert get_field(changeset, :state) == "backlog"
    end
  end

  describe "title/1" do
    test "extracts title from first heading" do
      issue = %Issue{body: "# Fix the bug\n\nSome details"}
      assert Issue.title(issue) == "Fix the bug"
    end

    test "extracts title from heading with extra spaces" do
      issue = %Issue{body: "# Fix the bug  \n\nSome details"}
      assert Issue.title(issue) == "Fix the bug"
    end

    test "extracts first heading when multiple exist" do
      issue = %Issue{body: "# First\n\n## Second\n\n# Third"}
      assert Issue.title(issue) == "First"
    end

    test "returns Unnamed for nil body" do
      assert Issue.title(%Issue{body: nil}) == "Unnamed"
    end

    test "returns Unnamed for empty body" do
      assert Issue.title(%Issue{body: ""}) == "Unnamed"
    end

    test "returns Unnamed when no heading present" do
      issue = %Issue{body: "Just some text without a heading"}
      assert Issue.title(issue) == "Unnamed"
    end

    test "does not match ## headings as title" do
      issue = %Issue{body: "## Not a title\n\nSome text"}
      assert Issue.title(issue) == "Unnamed"
    end
  end
end
