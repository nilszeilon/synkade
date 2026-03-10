defmodule Synkade.IssuesTest do
  use Synkade.DataCase, async: true

  alias Synkade.Issues
  alias Synkade.Issues.Issue

  defp create_project(_) do
    {:ok, project} = Synkade.Settings.create_project(%{name: "test-project"})
    %{project: project}
  end

  setup :create_project

  describe "create_issue/1" do
    test "creates issue with valid attrs", %{project: project} do
      assert {:ok, %Issue{} = issue} =
               Issues.create_issue(%{title: "Fix bug", project_id: project.id})

      assert issue.title == "Fix bug"
      assert issue.state == "backlog"
      assert issue.depth == 0
    end

    test "auto-computes depth from parent", %{project: project} do
      {:ok, parent} = Issues.create_issue(%{title: "Parent", project_id: project.id})
      {:ok, child} = Issues.create_issue(%{title: "Child", project_id: project.id, parent_id: parent.id})
      assert child.depth == 1
      assert child.parent_id == parent.id
    end

    test "returns error for missing title", %{project: project} do
      assert {:error, changeset} = Issues.create_issue(%{project_id: project.id})
      assert errors_on(changeset).title
    end

    test "broadcasts issues_updated", %{project: project} do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Issues.pubsub_topic())
      {:ok, _} = Issues.create_issue(%{title: "Test", project_id: project.id})
      assert_receive {:issues_updated}
    end
  end

  describe "list_issues/2" do
    test "lists issues for a project", %{project: project} do
      {:ok, _} = Issues.create_issue(%{title: "A", project_id: project.id})
      {:ok, _} = Issues.create_issue(%{title: "B", project_id: project.id})
      issues = Issues.list_issues(project.id)
      assert length(issues) == 2
    end

    test "filters by state", %{project: project} do
      {:ok, _} = Issues.create_issue(%{title: "Backlog", project_id: project.id})
      {:ok, _} = Issues.create_issue(%{title: "Queued", project_id: project.id, state: "queued"})
      assert [%{title: "Queued"}] = Issues.list_issues(project.id, state: "queued")
    end

    test "filters by parent_id", %{project: project} do
      {:ok, parent} = Issues.create_issue(%{title: "Parent", project_id: project.id})
      {:ok, _} = Issues.create_issue(%{title: "Child", project_id: project.id, parent_id: parent.id})
      {:ok, _} = Issues.create_issue(%{title: "Root", project_id: project.id})

      children = Issues.list_issues(project.id, parent_id: parent.id)
      assert length(children) == 1
      assert hd(children).title == "Child"
    end
  end

  describe "list_root_issues/1" do
    test "lists only root issues with children preloaded", %{project: project} do
      {:ok, parent} = Issues.create_issue(%{title: "Root", project_id: project.id})
      {:ok, _} = Issues.create_issue(%{title: "Child", project_id: project.id, parent_id: parent.id})

      roots = Issues.list_root_issues(project.id)
      assert length(roots) == 1
      root = hd(roots)
      assert root.title == "Root"
      assert length(root.children) == 1
      assert hd(root.children).title == "Child"
    end
  end

  describe "get_issue!/1" do
    test "returns issue with children preloaded", %{project: project} do
      {:ok, parent} = Issues.create_issue(%{title: "Parent", project_id: project.id})
      {:ok, child} = Issues.create_issue(%{title: "Child", project_id: project.id, parent_id: parent.id})

      fetched = Issues.get_issue!(parent.id)
      assert fetched.id == parent.id
      assert length(fetched.children) == 1
      assert hd(fetched.children).id == child.id
    end

    test "raises for nonexistent ID" do
      assert_raise Ecto.NoResultsError, fn ->
        Issues.get_issue!(Ecto.UUID.generate())
      end
    end
  end

  describe "update_issue/2" do
    test "updates issue fields", %{project: project} do
      {:ok, issue} = Issues.create_issue(%{title: "Original", project_id: project.id})
      {:ok, updated} = Issues.update_issue(issue, %{title: "Updated"})
      assert updated.title == "Updated"
    end
  end

  describe "delete_issue/1" do
    test "deletes issue", %{project: project} do
      {:ok, issue} = Issues.create_issue(%{title: "Delete me", project_id: project.id})
      {:ok, _} = Issues.delete_issue(issue)

      assert_raise Ecto.NoResultsError, fn ->
        Issues.get_issue!(issue.id)
      end
    end
  end

  describe "transition_state/2" do
    test "backlog -> queued", %{project: project} do
      {:ok, issue} = Issues.create_issue(%{title: "Test", project_id: project.id, state: "backlog"})
      assert {:ok, updated} = Issues.transition_state(issue, "queued")
      assert updated.state == "queued"
    end

    test "queued -> in_progress", %{project: project} do
      {:ok, issue} = Issues.create_issue(%{title: "Test", project_id: project.id, state: "queued"})
      assert {:ok, updated} = Issues.transition_state(issue, "in_progress")
      assert updated.state == "in_progress"
    end

    test "in_progress -> awaiting_review", %{project: project} do
      {:ok, issue} = Issues.create_issue(%{title: "Test", project_id: project.id, state: "in_progress"})
      assert {:ok, updated} = Issues.transition_state(issue, "awaiting_review")
      assert updated.state == "awaiting_review"
    end

    test "in_progress -> done", %{project: project} do
      {:ok, issue} = Issues.create_issue(%{title: "Test", project_id: project.id, state: "in_progress"})
      assert {:ok, updated} = Issues.transition_state(issue, "done")
      assert updated.state == "done"
    end

    test "awaiting_review -> done", %{project: project} do
      {:ok, issue} = Issues.create_issue(%{title: "Test", project_id: project.id, state: "awaiting_review"})
      assert {:ok, updated} = Issues.transition_state(issue, "done")
      assert updated.state == "done"
    end

    test "any -> cancelled", %{project: project} do
      for state <- ~w(backlog queued in_progress awaiting_review done) do
        {:ok, issue} = Issues.create_issue(%{title: "Test #{state}", project_id: project.id, state: state})
        assert {:ok, updated} = Issues.transition_state(issue, "cancelled")
        assert updated.state == "cancelled"
      end
    end

    test "rejects invalid transition", %{project: project} do
      {:ok, issue} = Issues.create_issue(%{title: "Test", project_id: project.id, state: "backlog"})
      assert {:error, :invalid_transition} = Issues.transition_state(issue, "done")
    end

    test "cancelled has no transitions", %{project: project} do
      {:ok, issue} = Issues.create_issue(%{title: "Test", project_id: project.id, state: "cancelled"})
      assert {:error, :invalid_transition} = Issues.transition_state(issue, "backlog")
    end
  end

  describe "convenience functions" do
    test "queue_issue/1", %{project: project} do
      {:ok, issue} = Issues.create_issue(%{title: "Test", project_id: project.id})
      assert {:ok, %{state: "queued"}} = Issues.queue_issue(issue)
    end

    test "complete_issue/1", %{project: project} do
      {:ok, issue} = Issues.create_issue(%{title: "Test", project_id: project.id, state: "in_progress"})
      assert {:ok, %{state: "done"}} = Issues.complete_issue(issue)
    end

    test "cancel_issue/1", %{project: project} do
      {:ok, issue} = Issues.create_issue(%{title: "Test", project_id: project.id})
      assert {:ok, %{state: "cancelled"}} = Issues.cancel_issue(issue)
    end
  end

  describe "ancestor_chain/1" do
    test "returns empty for root issue", %{project: project} do
      {:ok, root} = Issues.create_issue(%{title: "Root", project_id: project.id})
      root = Issues.get_issue!(root.id)
      assert Issues.ancestor_chain(root) == []
    end

    test "returns chain for nested issue", %{project: project} do
      {:ok, root} = Issues.create_issue(%{title: "Root", project_id: project.id})
      {:ok, child} = Issues.create_issue(%{title: "Child", project_id: project.id, parent_id: root.id})
      {:ok, grandchild} = Issues.create_issue(%{title: "Grandchild", project_id: project.id, parent_id: child.id})

      grandchild = Issues.get_issue!(grandchild.id)
      chain = Issues.ancestor_chain(grandchild)
      assert length(chain) == 2
      assert Enum.map(chain, & &1.title) == ["Root", "Child"]
    end
  end

  describe "list_queued_issues/1" do
    test "returns queued issues ordered by priority", %{project: project} do
      {:ok, _} = Issues.create_issue(%{title: "Low", project_id: project.id, state: "queued", priority: 3})
      {:ok, _} = Issues.create_issue(%{title: "High", project_id: project.id, state: "queued", priority: 1})
      {:ok, _} = Issues.create_issue(%{title: "Backlog", project_id: project.id, state: "backlog"})

      queued = Issues.list_queued_issues(project.id)
      assert length(queued) == 2
      assert Enum.map(queued, & &1.title) == ["High", "Low"]
    end
  end

  describe "create_children_from_agent/2" do
    test "creates children with correct depth and project", %{project: project} do
      {:ok, parent} = Issues.create_issue(%{title: "Parent", project_id: project.id})

      children_attrs = [
        %{title: "Sub-task 1", description: "Do thing 1"},
        %{title: "Sub-task 2", description: "Fix thing 2", priority: 2}
      ]

      results = Issues.create_children_from_agent(parent, children_attrs)
      assert length(results) == 2
      assert Enum.all?(results, &match?({:ok, _}, &1))

      children = Issues.list_children(parent.id)
      assert length(children) == 2
      assert Enum.all?(children, &(&1.depth == 1))
      assert Enum.all?(children, &(&1.project_id == project.id))
      assert Enum.all?(children, &(&1.parent_id == parent.id))
      assert Enum.all?(children, &(&1.state == "backlog"))
    end
  end
end
