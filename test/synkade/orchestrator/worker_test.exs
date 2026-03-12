defmodule Synkade.Orchestrator.WorkerTest do
  use ExUnit.Case, async: true

  alias Synkade.Orchestrator.Worker
  alias Synkade.Agent.Event

  describe "extract_pr_url/1" do
    test "extracts PR URL from session events" do
      session = %{
        events: [
          %Event{type: "assistant", message: "I'll work on this."},
          %Event{type: "result", message: "Created PR: https://github.com/acme/api/pull/42"}
        ]
      }

      assert {:ok, "https://github.com/acme/api/pull/42"} = Worker.extract_pr_url(session)
    end

    test "returns most recent PR URL when multiple exist" do
      session = %{
        events: [
          %Event{type: "assistant", message: "See https://github.com/acme/api/pull/1"},
          %Event{type: "result", message: "Final PR: https://github.com/acme/api/pull/99"}
        ]
      }

      # Events are reversed, so last event is checked first
      assert {:ok, "https://github.com/acme/api/pull/99"} = Worker.extract_pr_url(session)
    end

    test "returns :none when no PR URL found" do
      session = %{
        events: [
          %Event{type: "assistant", message: "I fixed the bug."},
          %Event{type: "result", message: "Done!"}
        ]
      }

      assert :none = Worker.extract_pr_url(session)
    end

    test "returns :none for empty events" do
      session = %{events: []}
      assert :none = Worker.extract_pr_url(session)
    end

    test "skips events with nil messages" do
      session = %{
        events: [
          %Event{type: "system", message: nil},
          %Event{type: "result", message: "PR: https://github.com/acme/api/pull/5"}
        ]
      }

      assert {:ok, "https://github.com/acme/api/pull/5"} = Worker.extract_pr_url(session)
    end

    test "handles malformed URLs (no match)" do
      session = %{
        events: [
          %Event{type: "result", message: "See https://github.com/acme/api/issues/42"}
        ]
      }

      assert :none = Worker.extract_pr_url(session)
    end

    test "extracts URL embedded in longer text" do
      session = %{
        events: [
          %Event{
            type: "result",
            message:
              "I've created a pull request at https://github.com/org/repo/pull/123 for your review."
          }
        ]
      }

      assert {:ok, "https://github.com/org/repo/pull/123"} = Worker.extract_pr_url(session)
    end
  end
end
