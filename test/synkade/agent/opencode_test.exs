defmodule Synkade.Agent.OpenCodeTest do
  use ExUnit.Case, async: true

  alias Synkade.Agent.OpenCode
  alias Synkade.Agent.Event

  describe "build_args/3" do
    test "builds default args with prompt last" do
      config = %{}
      args = OpenCode.build_args(config, "Fix the bug", [])

      assert args == ["run", "--format", "json", "--thinking", "Fix the bug"]
    end

    test "includes model when specified" do
      config = %{"agent" => %{"model" => "openrouter/anthropic/claude-sonnet-4-5-20250929"}}
      args = OpenCode.build_args(config, "prompt", [])

      assert args == [
               "run",
               "--format",
               "json",
               "--thinking",
               "--model",
               "openrouter/anthropic/claude-sonnet-4-5-20250929",
               "prompt"
             ]
    end

    test "includes --continue for continuation" do
      config = %{}
      args = OpenCode.build_args(config, "continue work", ["--continue"])

      assert "--continue" in args
      assert List.last(args) == "continue work"
    end

    test "prompt is always the last argument" do
      config = %{"agent" => %{"model" => "openrouter/some-model"}}
      args = OpenCode.build_args(config, "my prompt", ["--continue"])

      assert List.last(args) == "my prompt"
    end
  end

  describe "build_env/1" do
    test "sets OPENROUTER_API_KEY from api_key" do
      config = %{"agent" => %{"api_key" => "sk-or-test-123"}}
      env = OpenCode.build_env(config)

      assert {~c"OPENROUTER_API_KEY", ~c"sk-or-test-123"} in env
      refute Enum.any?(env, fn {k, _} -> k == ~c"ANTHROPIC_API_KEY" end)
    end

    test "returns empty list when no api_key" do
      config = %{"agent" => %{}}
      env = OpenCode.build_env(config)

      refute Enum.any?(env, fn {k, _} -> k == ~c"OPENROUTER_API_KEY" end)
    end

    test "includes GITHUB_TOKEN from tracker api_key" do
      config = %{
        "agent" => %{"api_key" => "sk-or-test"},
        "tracker" => %{"api_key" => "ghp_pat_token"}
      }

      env = OpenCode.build_env(config)
      assert {~c"GITHUB_TOKEN", ~c"ghp_pat_token"} in env
      assert {~c"OPENROUTER_API_KEY", ~c"sk-or-test"} in env
    end

    test "includes SYNKADE_API_URL and SYNKADE_API_TOKEN" do
      config = %{
        "agent" => %{
          "api_key" => "sk-or-test",
          "synkade_api_url" => "http://localhost:4000",
          "synkade_api_token" => "tok_abc"
        }
      }

      env = OpenCode.build_env(config)
      assert {~c"SYNKADE_API_URL", ~c"http://localhost:4000"} in env
      assert {~c"SYNKADE_API_TOKEN", ~c"tok_abc"} in env
    end
  end

  describe "parse_event/1" do
    test "parses text event with part.text" do
      json =
        Jason.encode!(%{
          "type" => "text",
          "sessionID" => "ses_abc123",
          "part" => %{
            "type" => "text",
            "text" => "Hello! How can I help?",
            "tokens" => %{"input" => 50, "output" => 25, "total" => 75}
          }
        })

      assert {:ok, %Event{} = event} = OpenCode.parse_event(json)
      assert event.type == "text"
      assert event.session_id == "ses_abc123"
      assert event.message == "Hello! How can I help?"
    end

    test "parses step_finish event with tokens" do
      json =
        Jason.encode!(%{
          "type" => "step_finish",
          "sessionID" => "ses_abc123",
          "part" => %{
            "type" => "step-finish",
            "reason" => "stop",
            "tokens" => %{"input" => 100, "output" => 50, "total" => 150}
          }
        })

      assert {:ok, %Event{} = event} = OpenCode.parse_event(json)
      assert event.type == "step_finish"
      assert event.input_tokens == 100
      assert event.output_tokens == 50
      assert event.total_tokens == 150
    end

    test "parses error event" do
      json =
        Jason.encode!(%{
          "type" => "error",
          "sessionID" => "ses_abc123",
          "error" => %{"name" => "UnknownError", "message" => "Model not found"}
        })

      assert {:ok, %Event{} = event} = OpenCode.parse_event(json)
      assert event.type == "error"
      assert event.message == "Model not found"
    end

    test "skips non-JSON lines" do
      assert :skip = OpenCode.parse_event("not json")
      assert :skip = OpenCode.parse_event("")
    end

    test "handles missing usage gracefully" do
      json = Jason.encode!(%{"type" => "step_start", "sessionID" => "ses_abc"})
      assert {:ok, event} = OpenCode.parse_event(json)
      assert event.input_tokens == 0
      assert event.output_tokens == 0
      assert event.total_tokens == 0
    end
  end
end
