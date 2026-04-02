defmodule Synkade.Execution.AgentRunnerRateLimitTest do
  use ExUnit.Case, async: true

  alias Synkade.Execution.AgentRunner
  alias Synkade.Agent.Event

  describe "detect_rate_limit/1 — usage cap (plan/billing exhausted)" do
    test "detects usage limit exceeded" do
      session =
        session_with_messages(["Usage limit exceeded. Check your plan and billing details."])

      assert {:usage_cap, %{reason: reason}} = AgentRunner.detect_rate_limit(session)
      assert reason =~ "usage limit exceeded"
    end

    test "detects insufficient_quota" do
      session = session_with_messages(["Error: insufficient_quota for this API key"])
      assert {:usage_cap, %{reason: reason}} = AgentRunner.detect_rate_limit(session)
      assert reason =~ "insufficient_quota"
    end

    test "detects billing_hard_limit_reached" do
      session = session_with_messages(["billing_hard_limit_reached"])
      assert {:usage_cap, _} = AgentRunner.detect_rate_limit(session)
    end

    test "detects credit balance is too low" do
      session = session_with_messages(["Your credit balance is too low"])
      assert {:usage_cap, _} = AgentRunner.detect_rate_limit(session)
    end

    test "detects quota exceeded" do
      session =
        session_with_messages(["Quota exceeded. Check your plan and billing details."])

      assert {:usage_cap, _} = AgentRunner.detect_rate_limit(session)
    end

    test "detects exceeded your current quota" do
      session =
        session_with_messages([
          "Insufficient quota: You exceeded your current quota, please check your plan and billing details."
        ])

      assert {:usage_cap, _} = AgentRunner.detect_rate_limit(session)
    end
  end

  describe "detect_rate_limit/1 — temporary rate limit" do
    test "detects Anthropic rate_limit pattern" do
      session = session_with_messages(["Error: rate_limit - too many requests"])
      assert {:rate_limited, %{reason: reason}} = AgentRunner.detect_rate_limit(session)
      assert reason =~ "rate_limit"
    end

    test "detects 429 status code" do
      session = session_with_messages(["HTTP 429"])
      assert {:rate_limited, _} = AgentRunner.detect_rate_limit(session)
    end

    test "detects overloaded" do
      session = session_with_messages(["Error: overloaded"])
      assert {:rate_limited, _} = AgentRunner.detect_rate_limit(session)
    end

    test "detects rate limit in raw event data" do
      session = %{
        events: [
          %Event{
            type: "error",
            message: nil,
            raw: %{"error" => %{"type" => "rate_limit"}},
            input_tokens: 0,
            output_tokens: 0,
            total_tokens: 0,
            timestamp: DateTime.utc_now()
          }
        ]
      }

      assert {:rate_limited, _} = AgentRunner.detect_rate_limit(session)
    end
  end

  describe "detect_rate_limit/1 — not rate limited" do
    test "returns :not_rate_limited for normal errors" do
      session = session_with_messages(["Error: file not found", "compilation failed"])
      assert :not_rate_limited = AgentRunner.detect_rate_limit(session)
    end

    test "returns :not_rate_limited for empty events" do
      session = %{events: []}
      assert :not_rate_limited = AgentRunner.detect_rate_limit(session)
    end
  end

  describe "usage cap takes priority over rate limit" do
    test "message containing both patterns returns :usage_cap" do
      session =
        session_with_messages([
          "429 insufficient_quota: You exceeded your current quota"
        ])

      assert {:usage_cap, _} = AgentRunner.detect_rate_limit(session)
    end
  end

  describe "retry hint extraction" do
    test "extracts retry_delay_ms from Claude Code api_retry events" do
      session = %{
        events: [
          %Event{
            type: "system",
            message: "rate_limit",
            raw: %{"subtype" => "api_retry", "retry_delay_ms" => 30_000},
            input_tokens: 0,
            output_tokens: 0,
            total_tokens: 0,
            timestamp: DateTime.utc_now()
          }
        ]
      }

      assert {:rate_limited, %{retry_after_seconds: 30}} =
               AgentRunner.detect_rate_limit(session)
    end

    test "extracts resets_in_seconds from Codex rate_limits" do
      session = %{
        events: [
          %Event{
            type: "event_msg",
            message: "rate_limit",
            raw: %{
              "rate_limits" => %{
                "primary" => %{"resets_in_seconds" => 17940, "used_percent" => 100.0}
              }
            },
            input_tokens: 0,
            output_tokens: 0,
            total_tokens: 0,
            timestamp: DateTime.utc_now()
          }
        ]
      }

      assert {:rate_limited, %{retry_after_seconds: 17940}} =
               AgentRunner.detect_rate_limit(session)
    end

    test "parses 'Try again in Ns' from error messages" do
      session = session_with_messages(["Rate limit hit. Try again in 45s"])
      assert {:rate_limited, %{retry_after_seconds: 45}} = AgentRunner.detect_rate_limit(session)
    end

    test "parses 'Try again in Nm' from error messages" do
      session = session_with_messages(["Rate limit hit. Try again in 5m"])

      assert {:rate_limited, %{retry_after_seconds: 300}} =
               AgentRunner.detect_rate_limit(session)
    end

    test "returns nil retry_after_seconds when no hint available" do
      session = session_with_messages(["Error: 429 too many requests"])

      assert {:rate_limited, %{retry_after_seconds: nil}} =
               AgentRunner.detect_rate_limit(session)
    end
  end

  defp session_with_messages(messages) do
    events =
      Enum.map(messages, fn msg ->
        %Event{
          type: "stderr",
          message: msg,
          raw: nil,
          input_tokens: 0,
          output_tokens: 0,
          total_tokens: 0,
          timestamp: DateTime.utc_now()
        }
      end)

    %{events: events}
  end
end
