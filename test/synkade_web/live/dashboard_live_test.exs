defmodule SynkadeWeb.DashboardLiveTest do
  use SynkadeWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Synkade.Jobs

  setup :register_and_log_in_user

  test "renders overview page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "Overview"
  end

  test "updates config_error in real-time", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, "/")

    snapshot = %{
      running: %{},
      retry_attempts: %{},
      awaiting_review: %{},
      agent_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, runtime_seconds: 0.0},
      agent_totals_by_project: %{},
      projects: %{},
      config_error: "Config file missing"
    }

    Phoenix.PubSub.broadcast(
      Synkade.PubSub,
      Jobs.pubsub_topic(scope),
      {:state_changed, snapshot}
    )

    html = render(view)
    assert html =~ "Config file missing"
  end
end
