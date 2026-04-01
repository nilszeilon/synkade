defmodule Synkade.IssuesTest do
  use Synkade.DataCase

  import Synkade.AccountsFixtures

  alias Synkade.Issues
  alias Synkade.Issues.Issue

  defp create_project(_) do
    scope = user_scope_fixture()
    {:ok, project} = Synkade.Settings.create_project(scope, %{name: "test-project"})
    %{project: project, scope: scope}
  end

  setup :create_project

  describe "create_issue/1" do
    test "creates issue with valid attrs", %{project: project} do
      assert {:ok, %Issue{} = issue} =
               Issues.create_issue(%{body: "# Fix bug", project_id: project.id})

      assert issue.body == "# Fix bug"
      assert Issue.title(issue) == "Fix bug"
      assert issue.state == "backlog"
      assert issue.depth == 0
    end

    test "creates issue without body", %{project: project} do
      assert {:ok, %Issue{} = issue} =
               Issues.create_issue(%{project_id: project.id})

      assert issue.body == nil
      assert Issue.title(issue) == "Unnamed"
    end

    test "auto-computes depth from parent", %{project: project} do
      {:ok, parent} = Issues.create_issue(%{body: "# Parent", project_id: project.id})

      {:ok, child} =
        Issues.create_issue(%{body: "# Child", project_id: project.id, parent_id: parent.id})

      assert child.depth == 1
      assert child.parent_id == parent.id
    end

    test "broadcasts issues_updated", %{project: project, scope: scope} do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Issues.pubsub_topic(scope.user.id))
      {:ok, _} = Issues.create_issue(%{body: "# Test", project_id: project.id})
      assert_receive {:issues_updated}
    end
  end

  describe "list_issues/2" do
    test "lists issues for a project", %{project: project} do
      {:ok, _} = Issues.create_issue(%{body: "# A", project_id: project.id})
      {:ok, _} = Issues.create_issue(%{body: "# B", project_id: project.id})
      issues = Issues.list_issues(project.id)
      assert length(issues) == 2
    end

    test "filters by state", %{project: project} do
      {:ok, _} = Issues.create_issue(%{body: "# Backlog", project_id: project.id})

      {:ok, _} =
        Issues.create_issue(%{body: "# Worked On", project_id: project.id, state: "worked_on"})

      worked_on = Issues.list_issues(project.id, state: "worked_on")
      assert length(worked_on) == 1
      assert Issue.title(hd(worked_on)) == "Worked On"
    end

    test "filters by parent_id", %{project: project} do
      {:ok, parent} = Issues.create_issue(%{body: "# Parent", project_id: project.id})

      {:ok, _} =
        Issues.create_issue(%{body: "# Child", project_id: project.id, parent_id: parent.id})

      {:ok, _} = Issues.create_issue(%{body: "# Root", project_id: project.id})

      children = Issues.list_issues(project.id, parent_id: parent.id)
      assert length(children) == 1
      assert Issue.title(hd(children)) == "Child"
    end
  end

  describe "get_issue!/1" do
    test "returns issue with children preloaded", %{project: project} do
      {:ok, parent} = Issues.create_issue(%{body: "# Parent", project_id: project.id})

      {:ok, child} =
        Issues.create_issue(%{body: "# Child", project_id: project.id, parent_id: parent.id})

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
      {:ok, issue} = Issues.create_issue(%{body: "# Original", project_id: project.id})
      {:ok, updated} = Issues.update_issue(issue, %{body: "# Updated"})
      assert updated.body == "# Updated"
      assert Issue.title(updated) == "Updated"
    end
  end

  describe "delete_issue/1" do
    test "deletes issue", %{project: project} do
      {:ok, issue} = Issues.create_issue(%{body: "# Delete me", project_id: project.id})
      {:ok, _} = Issues.delete_issue(issue)

      assert_raise Ecto.NoResultsError, fn ->
        Issues.get_issue!(issue.id)
      end
    end
  end

  describe "transition_state/2" do
    test "backlog -> worked_on", %{project: project} do
      {:ok, issue} =
        Issues.create_issue(%{body: "# Test", project_id: project.id, state: "backlog"})

      assert {:ok, updated} = Issues.transition_state(issue, "worked_on")
      assert updated.state == "worked_on"
    end

    test "backlog -> done", %{project: project} do
      {:ok, issue} =
        Issues.create_issue(%{body: "# Test", project_id: project.id, state: "backlog"})

      assert {:ok, updated} = Issues.transition_state(issue, "done")
      assert updated.state == "done"
    end

    test "worked_on -> done", %{project: project} do
      {:ok, issue} =
        Issues.create_issue(%{body: "# Test", project_id: project.id, state: "worked_on"})

      assert {:ok, updated} = Issues.transition_state(issue, "done")
      assert updated.state == "done"
    end

    test "worked_on -> backlog", %{project: project} do
      {:ok, issue} =
        Issues.create_issue(%{body: "# Test", project_id: project.id, state: "worked_on"})

      assert {:ok, updated} = Issues.transition_state(issue, "backlog")
      assert updated.state == "backlog"
    end

    test "done -> backlog (reopen)", %{project: project} do
      {:ok, issue} =
        Issues.create_issue(%{body: "# Test", project_id: project.id, state: "done"})

      assert {:ok, reopened} = Issues.transition_state(issue, "backlog")
      assert reopened.state == "backlog"
    end

    test "rejects invalid transition", %{project: project} do
      {:ok, issue} =
        Issues.create_issue(%{body: "# Test", project_id: project.id, state: "done"})

      assert {:error, :invalid_transition} = Issues.transition_state(issue, "worked_on")
    end
  end

  describe "convenience functions" do
    test "complete_issue/1", %{project: project} do
      {:ok, issue} =
        Issues.create_issue(%{body: "# Test", project_id: project.id, state: "worked_on"})

      assert {:ok, %{state: "done"}} = Issues.complete_issue(issue)
    end

  end

  describe "ancestor_chain/1" do
    test "returns empty for root issue", %{project: project} do
      {:ok, root} = Issues.create_issue(%{body: "# Root", project_id: project.id})
      root = Issues.get_issue!(root.id)
      assert Issues.ancestor_chain(root) == []
    end

    test "returns chain for nested issue", %{project: project} do
      {:ok, root} = Issues.create_issue(%{body: "# Root", project_id: project.id})

      {:ok, child} =
        Issues.create_issue(%{body: "# Child", project_id: project.id, parent_id: root.id})

      {:ok, grandchild} =
        Issues.create_issue(%{
          body: "# Grandchild",
          project_id: project.id,
          parent_id: child.id
        })

      grandchild = Issues.get_issue!(grandchild.id)
      chain = Issues.ancestor_chain(grandchild)
      assert length(chain) == 2
      assert Enum.map(chain, &Issue.title/1) == ["Root", "Child"]
    end
  end

  describe "list_worked_on_issues/1" do
    test "returns worked_on issues ordered by inserted_at (FIFO)", %{project: project} do
      {:ok, _} =
        Issues.create_issue(%{body: "# First", project_id: project.id, state: "worked_on"})

      {:ok, _} =
        Issues.create_issue(%{body: "# Second", project_id: project.id, state: "worked_on"})

      {:ok, _} =
        Issues.create_issue(%{body: "# Backlog", project_id: project.id, state: "backlog"})

      worked_on = Issues.list_worked_on_issues(project.id)
      assert length(worked_on) == 2
      assert Enum.map(worked_on, &Issue.title/1) == ["First", "Second"]
    end
  end

  describe "dispatch_issue/3" do
    test "sets dispatch_message and transitions to worked_on", %{project: project} do
      {:ok, issue} = Issues.create_issue(%{body: "# Research X", project_id: project.id})
      {:ok, dispatched} = Issues.dispatch_issue(issue, "look into how we can do X")
      assert dispatched.state == "worked_on"

      reloaded = Issues.get_issue!(issue.id)
      assert reloaded.dispatch_message == "look into how we can do X"
    end

    test "sets assigned_agent_id when provided", %{project: project, scope: scope} do
      {:ok, agent} =
        Synkade.Settings.create_agent(scope, %{kind: "claude"})

      {:ok, issue} = Issues.create_issue(%{body: "# Research Y", project_id: project.id})
      {:ok, dispatched} = Issues.dispatch_issue(issue, "investigate Y", agent.id)
      assert dispatched.state == "worked_on"

      reloaded = Issues.get_issue!(issue.id)
      assert reloaded.dispatch_message == "investigate Y"
      assert reloaded.assigned_agent_id == agent.id
    end

    test "re-dispatches from done state", %{project: project} do
      {:ok, issue} =
        Issues.create_issue(%{body: "# Done issue", project_id: project.id, state: "done"})

      {:ok, dispatched} = Issues.dispatch_issue(issue, "try again")
      assert dispatched.state == "worked_on"
    end
  end

  describe "recurring issues" do
    test "creates issue with recurring fields", %{project: project} do
      {:ok, issue} =
        Issues.create_issue(%{
          body: "# Nightly build",
          project_id: project.id,
          recurring: true,
          recurrence_interval: 8,
          recurrence_unit: "days"
        })

      assert issue.recurring == true
      assert issue.recurrence_interval == 8
      assert issue.recurrence_unit == "days"
    end

    test "list_due_recurring_issues returns due issues", %{project: project} do
      {:ok, issue} =
        Issues.create_issue(%{
          body: "# Due recurring",
          project_id: project.id,
          state: "worked_on",
          recurring: true,
          recurrence_interval: 1
        })

      # Transition to done
      {:ok, done} = Issues.transition_state(issue, "done")

      # Backdate updated_at so interval has elapsed
      past = DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.truncate(:second)

      done
      |> Ecto.Changeset.change(updated_at: past)
      |> Synkade.Repo.update!()

      due = Issues.list_due_recurring_issues()
      assert length(due) == 1
      assert hd(due).id == done.id
    end

    test "list_due_recurring_issues excludes not-yet-due issues", %{project: project} do
      {:ok, issue} =
        Issues.create_issue(%{
          body: "# Not yet due",
          project_id: project.id,
          state: "worked_on",
          recurring: true,
          recurrence_interval: 24
        })

      {:ok, _done} = Issues.transition_state(issue, "done")

      # updated_at is now, interval is 24h — not due yet
      due = Issues.list_due_recurring_issues()
      assert due == []
    end

    test "list_due_recurring_issues excludes non-recurring done issues", %{project: project} do
      {:ok, issue} =
        Issues.create_issue(%{
          body: "# Not recurring",
          project_id: project.id,
          state: "worked_on",
          recurring: false
        })

      {:ok, _done} = Issues.transition_state(issue, "done")

      due = Issues.list_due_recurring_issues()
      assert due == []
    end

    test "cycle_recurring_issue transitions done→worked_on and appends system message", %{
      project: project
    } do
      {:ok, issue} =
        Issues.create_issue(%{
          body: "# Recurring task",
          project_id: project.id,
          state: "worked_on",
          recurring: true,
          recurrence_interval: 1
        })

      {:ok, done} = Issues.transition_state(issue, "done")
      {:ok, cycled} = Issues.cycle_recurring_issue(done)

      assert cycled.state == "worked_on"

      reloaded = Issues.get_issue!(cycled.id)
      messages = reloaded.metadata["messages"]
      assert length(messages) == 1
      assert hd(messages)["type"] == "system"
      assert hd(messages)["text"] == "Recurring issue cycled automatically"
    end
  end

  describe "create_children_from_agent/2" do
    test "creates children with correct depth and project", %{project: project} do
      {:ok, parent} = Issues.create_issue(%{body: "# Parent", project_id: project.id})

      children_attrs = [
        %{body: "# Sub-task 1\n\nDo thing 1"},
        %{body: "# Sub-task 2\n\nFix thing 2"}
      ]

      results = Issues.create_children_from_agent(parent, children_attrs)
      assert length(results) == 2
      assert Enum.all?(results, &match?({:ok, _}, &1))

      children = Issues.list_issues(project.id, parent_id: parent.id)
      assert length(children) == 2
      assert Enum.all?(children, &(&1.depth == 1))
      assert Enum.all?(children, &(&1.project_id == project.id))
      assert Enum.all?(children, &(&1.parent_id == parent.id))
      assert Enum.all?(children, &(&1.state == "backlog"))
    end
  end
end
