defmodule Synkade.Orchestrator.ReconcilerTest do
  use ExUnit.Case, async: true

  alias Synkade.Orchestrator.{Reconciler, State}

  defp make_config(plug_name) do
    %{
      "tracker" => %{
        "kind" => "github",
        "repo" => "acme/api",
        "api_key" => "test_token"
      },
      "__req_options__" => [plug: {Req.Test, plug_name}]
    }
  end

  defp make_state(plug_name, awaiting_review) do
    config = make_config(plug_name)

    %State{
      projects: %{
        "api" => %{
          name: "api",
          config: config,
          enabled: true
        }
      },
      awaiting_review: awaiting_review
    }
  end

  describe "check_pr_statuses/1" do
    test "marks merged PR for stop" do
      name = :reconciler_merged
      state = make_state(name, %{
        "api:42" => %{
          project_name: "api",
          issue_id: "42",
          identifier: "acme/api#42",
          pr_url: "https://github.com/acme/api/pull/10",
          pr_number: "10",
          env_ref: nil,
          session_id: nil,
          created_at: 0,
          agent_total_tokens: 100
        }
      })

      Req.Test.stub(name, fn conn ->
        Req.Test.json(conn, %{"state" => "closed", "merged" => true})
      end)

      result = Reconciler.check_pr_statuses(state)
      assert result.awaiting_review["api:42"].should_stop == :pr_merged
    end

    test "marks closed (unmerged) PR for stop" do
      name = :reconciler_closed
      state = make_state(name, %{
        "api:42" => %{
          project_name: "api",
          issue_id: "42",
          identifier: "acme/api#42",
          pr_url: "https://github.com/acme/api/pull/10",
          pr_number: "10",
          env_ref: nil,
          session_id: nil,
          created_at: 0,
          agent_total_tokens: 100
        }
      })

      Req.Test.stub(name, fn conn ->
        Req.Test.json(conn, %{"state" => "closed", "merged" => false})
      end)

      result = Reconciler.check_pr_statuses(state)
      assert result.awaiting_review["api:42"].should_stop == :pr_closed
    end

    test "leaves open PR unchanged" do
      name = :reconciler_open
      state = make_state(name, %{
        "api:42" => %{
          project_name: "api",
          issue_id: "42",
          identifier: "acme/api#42",
          pr_url: "https://github.com/acme/api/pull/10",
          pr_number: "10",
          env_ref: nil,
          session_id: nil,
          created_at: 0,
          agent_total_tokens: 100
        }
      })

      Req.Test.stub(name, fn conn ->
        Req.Test.json(conn, %{"state" => "open", "merged" => false})
      end)

      result = Reconciler.check_pr_statuses(state)
      refute Map.has_key?(result.awaiting_review["api:42"], :should_stop)
    end

    test "marks not found PR for stop" do
      name = :reconciler_not_found
      state = make_state(name, %{
        "api:42" => %{
          project_name: "api",
          issue_id: "42",
          identifier: "acme/api#42",
          pr_url: "https://github.com/acme/api/pull/999",
          pr_number: "999",
          env_ref: nil,
          session_id: nil,
          created_at: 0,
          agent_total_tokens: 100
        }
      })

      Req.Test.stub(name, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{"message" => "Not Found"}))
      end)

      result = Reconciler.check_pr_statuses(state)
      assert result.awaiting_review["api:42"].should_stop == :pr_not_found
    end

    test "handles API error gracefully" do
      name = :reconciler_error
      state = make_state(name, %{
        "api:42" => %{
          project_name: "api",
          issue_id: "42",
          identifier: "acme/api#42",
          pr_url: "https://github.com/acme/api/pull/10",
          pr_number: "10",
          env_ref: nil,
          session_id: nil,
          created_at: 0,
          agent_total_tokens: 100
        }
      })

      Req.Test.stub(name, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(500, Jason.encode!(%{"message" => "Internal Server Error"}))
      end)

      result = Reconciler.check_pr_statuses(state)
      # Should leave entry unchanged on error
      refute Map.has_key?(result.awaiting_review["api:42"], :should_stop)
    end

    test "handles empty awaiting_review" do
      name = :reconciler_empty
      state = make_state(name, %{})

      result = Reconciler.check_pr_statuses(state)
      assert result.awaiting_review == %{}
    end
  end
end
