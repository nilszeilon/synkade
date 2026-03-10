defmodule Synkade.Orchestrator.DispatchTest do
  use ExUnit.Case, async: true

  alias Synkade.Orchestrator.{Dispatch, State}
  alias Synkade.Tracker.Issue

  defp make_issue(attrs) do
    defaults = %{
      project_name: "api",
      id: "1",
      identifier: "acme/api#1",
      title: "Test issue",
      state: "open",
      labels: [],
      blocked_by: [],
      priority: nil,
      created_at: ~U[2024-01-15 10:00:00Z]
    }

    struct!(Issue, Map.merge(defaults, attrs))
  end

  defp make_project(overrides \\ %{}) do
    Map.merge(
      %{
        name: "api",
        config: %{"tracker" => %{"kind" => "github", "repo" => "acme/api", "labels" => []}},
        max_concurrent_agents: 10,
        enabled: true
      },
      overrides
    )
  end

  describe "filter_candidates/3" do
    test "filters out claimed issues" do
      issues = [make_issue(%{id: "1"}), make_issue(%{id: "2"})]
      state = %State{claimed: MapSet.new(["api:1"])}
      project = make_project()

      filtered = Dispatch.filter_candidates(issues, state, project)
      assert length(filtered) == 1
      assert hd(filtered).id == "2"
    end

    test "filters out running issues" do
      issues = [make_issue(%{id: "1"})]
      state = %State{running: %{"api:1" => %{project_name: "api"}}}
      project = make_project()

      filtered = Dispatch.filter_candidates(issues, state, project)
      assert filtered == []
    end

    test "filters out blocked issues" do
      blocked = make_issue(%{id: "1", blocked_by: [%{id: "10", identifier: "#10", state: "open"}]})
      unblocked = make_issue(%{id: "2", blocked_by: []})
      state = %State{}
      project = make_project()

      filtered = Dispatch.filter_candidates([blocked, unblocked], state, project)
      assert length(filtered) == 1
      assert hd(filtered).id == "2"
    end

    test "allows issues with closed blockers" do
      issue = make_issue(%{
        id: "1",
        blocked_by: [%{id: "10", identifier: "#10", state: "closed"}]
      })

      state = %State{}
      project = make_project()

      filtered = Dispatch.filter_candidates([issue], state, project)
      assert length(filtered) == 1
    end

    test "passes through all issues regardless of labels (DB handles filtering)" do
      a = make_issue(%{id: "1", labels: ["agent-ready", "bug"]})
      b = make_issue(%{id: "2", labels: ["docs"]})

      filtered = Dispatch.filter_candidates([a, b], %State{}, make_project())
      assert length(filtered) == 2
    end

    test "passes through all states (DB handles state filtering)" do
      open = make_issue(%{id: "1", state: "open"})
      closed = make_issue(%{id: "2", state: "closed"})

      filtered = Dispatch.filter_candidates([open, closed], %State{}, make_project())
      assert length(filtered) == 2
    end
  end

  describe "sort_candidates/1" do
    test "sorts by priority ascending" do
      a = make_issue(%{id: "1", priority: 3})
      b = make_issue(%{id: "2", priority: 1})
      c = make_issue(%{id: "3", priority: 2})

      sorted = Dispatch.sort_candidates([a, b, c])
      assert Enum.map(sorted, & &1.id) == ["2", "3", "1"]
    end

    test "sorts by created_at when priority is equal" do
      a = make_issue(%{id: "1", priority: 1, created_at: ~U[2024-01-20 10:00:00Z]})
      b = make_issue(%{id: "2", priority: 1, created_at: ~U[2024-01-10 10:00:00Z]})

      sorted = Dispatch.sort_candidates([a, b])
      assert Enum.map(sorted, & &1.id) == ["2", "1"]
    end

    test "nil priority sorts last" do
      a = make_issue(%{id: "1", priority: nil})
      b = make_issue(%{id: "2", priority: 1})

      sorted = Dispatch.sort_candidates([a, b])
      assert Enum.map(sorted, & &1.id) == ["2", "1"]
    end
  end

  describe "available_slots/2" do
    test "respects global limit" do
      state = %State{
        max_concurrent_agents: 3,
        running: %{"a:1" => %{project_name: "a"}, "a:2" => %{project_name: "a"}}
      }

      project = make_project(%{max_concurrent_agents: 10})
      assert Dispatch.available_slots(state, project) == 1
    end

    test "respects per-project limit" do
      state = %State{
        max_concurrent_agents: 10,
        running: %{
          "api:1" => %{project_name: "api"},
          "api:2" => %{project_name: "api"}
        }
      }

      project = make_project(%{max_concurrent_agents: 2})
      assert Dispatch.available_slots(state, project) == 0
    end

    test "returns min of global and project slots" do
      state = %State{
        max_concurrent_agents: 2,
        running: %{"other:1" => %{project_name: "other"}}
      }

      project = make_project(%{max_concurrent_agents: 5})
      assert Dispatch.available_slots(state, project) == 1
    end
  end
end
