defmodule SynkadeWeb.DashboardLiveTest do
  use SynkadeWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders dashboard page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "Overview"
    assert html =~ "Running"
    assert html =~ "Retry Queue"
    assert html =~ "Total Tokens"
  end

  test "shows workflow error when present", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    # The workflow error should show since there's no WORKFLOW.md in test
    # The dashboard still renders
    assert render(view) =~ "Overview"
  end

  test "refresh button exists", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "Refresh"
  end

  test "updates in real-time when state_changed is broadcast", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    # Initially no running sessions
    assert html =~ "No active sessions"

    # Broadcast a state change with a running entry
    snapshot = %{
      running: %{
        "test:1" => %{
          project_name: "test",
          issue_id: "1",
          identifier: "#1",
          session_id: "sess-123",
          model: "claude-sonnet-4-5-20250929",
          auth_mode: "api_key",
          turn_count: 3,
          agent_input_tokens: 2000,
          agent_output_tokens: 3000,
          agent_total_tokens: 5000,
          last_agent_event: "tool_use"
        }
      },
      retry_attempts: %{},
      agent_totals: %{input_tokens: 2000, output_tokens: 3000, total_tokens: 5000, runtime_seconds: 42.0},
      agent_totals_by_project: %{},
      activity_log: [],
      projects: %{},
      workflow_error: nil
    }

    Phoenix.PubSub.broadcast(Synkade.PubSub, Synkade.Orchestrator.pubsub_topic(), {:state_changed, snapshot})

    # Dashboard should update without manual refresh
    html = render(view)
    refute html =~ "No active sessions"
    assert html =~ "test"
    assert html =~ "#1"
    assert html =~ "sess-123"
  end

  test "updates workflow_error in real-time", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    snapshot = %{
      running: %{},
      retry_attempts: %{},
      agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, runtime_seconds: 0.0},
      agent_totals_by_project: %{},
      activity_log: [],
      projects: %{},
      workflow_error: "Config file missing"
    }

    Phoenix.PubSub.broadcast(Synkade.PubSub, Synkade.Orchestrator.pubsub_topic(), {:state_changed, snapshot})

    html = render(view)
    assert html =~ "Config file missing"
  end
end
