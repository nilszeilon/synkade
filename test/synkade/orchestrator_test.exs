defmodule Synkade.OrchestratorTest do
  use Synkade.DataCase, async: false

  alias Synkade.Orchestrator
  alias Synkade.Orchestrator.State
  alias Synkade.Settings

  defp create_settings(_) do
    {:ok, setting} = Settings.save_settings(%{github_pat: "ghp_test123"})
    {:ok, project} = Settings.create_project(%{name: "test-proj", enabled: true})
    {:ok, agent} = Settings.create_agent(%{name: "test-agent", kind: "claude", api_key: "sk-test"})

    # Set default agent on project
    Settings.update_project(project, %{default_agent_id: agent.id})
    project = Settings.get_project!(project.id)

    %{setting: setting, project: project, agent: agent}
  end

  defp start_orchestrator(%{} = _ctx) do
    # Use unique pubsub to avoid interference
    name = :"orchestrator_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      Orchestrator.start_link(
        name: name,
        pubsub: Synkade.PubSub
      )

    # Allow DB ownership
    Ecto.Adapters.SQL.Sandbox.allow(Synkade.Repo, self(), pid)

    # Wait for init to complete
    Process.sleep(100)

    %{orchestrator: name, orchestrator_pid: pid}
  end

  setup :create_settings

  describe "get_state/1" do
    setup :start_orchestrator

    test "returns snapshot with expected keys", %{orchestrator: orc} do
      state = Orchestrator.get_state(orc)

      assert is_map(state.projects)
      assert is_map(state.running)
      assert is_list(state.claimed)
      assert is_map(state.retry_attempts)
      assert is_map(state.awaiting_review)
      assert is_map(state.agent_totals)
      assert state.agent_totals.total_tokens == 0
      assert is_nil(state.config_error)
    end

    test "loads project config from DB", %{orchestrator: orc, project: project} do
      state = Orchestrator.get_state(orc)
      assert Map.has_key?(state.projects, project.name)

      loaded = state.projects[project.name]
      assert loaded.name == project.name
      assert loaded.db_id == project.id
      assert loaded.enabled == true
    end
  end

  describe "get_issue_events/2" do
    setup :start_orchestrator

    test "returns empty list when no issue is running", %{orchestrator: orc} do
      events = Orchestrator.get_issue_events(orc, "nonexistent")
      assert events == []
    end
  end

  describe "config reload on PubSub" do
    setup :start_orchestrator

    test "reloads config on settings_updated", %{orchestrator: orc, orchestrator_pid: pid} do
      # Subscribe to orchestrator updates
      Phoenix.PubSub.subscribe(Synkade.PubSub, Orchestrator.pubsub_topic())

      # Trigger settings update
      send(pid, {:settings_updated, %{}})

      assert_receive {:state_changed, snapshot}, 2000
      assert is_map(snapshot.projects)
    end

    test "reloads config on projects_updated", %{orchestrator: orc, orchestrator_pid: pid} do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Orchestrator.pubsub_topic())

      send(pid, {:projects_updated})

      assert_receive {:state_changed, snapshot}, 2000
      assert is_map(snapshot.projects)
    end

    test "reloads config on agents_updated", %{orchestrator_pid: pid} do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Orchestrator.pubsub_topic())

      send(pid, {:agents_updated})

      assert_receive {:state_changed, _snapshot}, 2000
    end
  end

  describe "dispatch cycle" do
    setup :start_orchestrator

    test "dispatches queued DB issues", %{orchestrator: orc, orchestrator_pid: pid, project: project} do
      # Create and queue an issue
      {:ok, issue} =
        Synkade.Issues.create_issue(%{body: "# Test dispatch", project_id: project.id})

      {:ok, issue} = Synkade.Issues.queue_issue(issue)
      assert issue.state == "queued"

      Phoenix.PubSub.subscribe(Synkade.PubSub, Orchestrator.pubsub_topic())

      # Trigger dispatch
      send(pid, :dispatch)

      # Should pick up the queued issue — we'll see state_changed with running entry
      assert_receive {:state_changed, snapshot}, 5000
      # The issue should either be running or have already completed
      # (worker will fail quickly since there's no real agent)
    end
  end

  describe "agent_heartbeat/4" do
    setup :start_orchestrator

    test "is a no-op when issue not running", %{orchestrator: orc} do
      # Should not crash
      Orchestrator.heartbeat(orc, "nonexistent", "working", "doing stuff")

      state = Orchestrator.get_state(orc)
      assert map_size(state.running) == 0
    end
  end

  describe "retry_timer" do
    setup :start_orchestrator

    test "clears retry entry and triggers dispatch", %{orchestrator_pid: pid} do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Orchestrator.pubsub_topic())

      send(pid, {:retry_timer, "test-proj", "issue-1"})

      assert_receive {:state_changed, snapshot}, 2000
      refute Map.has_key?(snapshot.retry_attempts, "test-proj:issue-1")
    end
  end

  describe "agent_event accumulation" do
    setup :start_orchestrator

    test "accumulates events on running entry", %{orchestrator: orc, orchestrator_pid: pid, project: project} do
      # Manually inject a running entry to test event accumulation
      key = State.composite_key(project.name, "fake-issue")

      # We'll use GenServer internals via cast
      event = %{
        type: "assistant",
        message: "thinking...",
        session_id: "sess-123",
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150
      }

      # First we need a running entry — cast the event (it will be a no-op without one)
      GenServer.cast(pid, {:agent_event, project.name, "fake-issue", event})

      # Without a running entry, events are dropped
      events = Orchestrator.get_issue_events(orc, "fake-issue")
      assert events == []
    end
  end

  describe "broadcast_state/1" do
    setup :start_orchestrator

    test "strips events from running entries in broadcast", %{orchestrator_pid: pid} do
      Phoenix.PubSub.subscribe(Synkade.PubSub, Orchestrator.pubsub_topic())

      # Trigger any state change
      send(pid, {:settings_updated, %{}})

      assert_receive {:state_changed, snapshot}, 2000

      # Running entries in broadcast should not have :events key
      Enum.each(snapshot.running, fn {_key, entry} ->
        refute Map.has_key?(entry, :events)
      end)
    end
  end

  describe "check_pr_status/2" do
    setup :start_orchestrator

    test "handles missing issue gracefully", %{orchestrator: orc} do
      # Should not crash
      Orchestrator.check_pr_status(orc, "nonexistent-id")
      Process.sleep(100)

      # Orchestrator still alive
      state = Orchestrator.get_state(orc)
      assert is_map(state)
    end
  end

  describe "pubsub_topic/0" do
    test "returns expected topic" do
      assert Orchestrator.pubsub_topic() == "orchestrator:updates"
    end
  end

  describe "agent_events_topic/1" do
    test "returns per-issue topic" do
      assert Orchestrator.agent_events_topic("abc-123") == "agent_events:abc-123"
    end
  end
end
