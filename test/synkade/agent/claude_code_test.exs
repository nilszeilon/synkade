defmodule Synkade.Agent.ClaudeCodeTest do
  use ExUnit.Case, async: true

  alias Synkade.Agent.ClaudeCode
  alias Synkade.Agent.Event

  describe "build_args/3" do
    test "builds default args" do
      config = %{}
      args = ClaudeCode.build_args(config, "Fix the bug", [])

      assert "-p" in args
      assert "Fix the bug" in args
      assert "--output-format" in args
      assert "stream-json" in args
      assert "--verbose" in args
      refute "--allowedTools" in args
    end

    test "includes model when specified" do
      config = %{"agent" => %{"model" => "claude-sonnet-4-5-20250929"}}
      args = ClaudeCode.build_args(config, "prompt", [])

      idx = Enum.find_index(args, &(&1 == "--model"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "claude-sonnet-4-5-20250929"
    end

    test "includes resume flag for continuation" do
      config = %{}
      args = ClaudeCode.build_args(config, "continue", ["--resume", "session_abc"])

      assert "--resume" in args
      assert "session_abc" in args
    end

    test "includes max-tokens when specified" do
      config = %{"agent" => %{"max_tokens" => 4096}}
      args = ClaudeCode.build_args(config, "prompt", [])

      idx = Enum.find_index(args, &(&1 == "--max-tokens"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "4096"
    end

    test "does not include allowed tools flag" do
      config = %{"agent" => %{}}
      args = ClaudeCode.build_args(config, "prompt", [])

      refute Enum.member?(args, "--allowedTools")
    end
  end

  describe "build_env/1" do
    test "sets ANTHROPIC_API_KEY for api_key auth mode" do
      config = %{"agent" => %{"auth_mode" => "api_key", "api_key" => "sk-test-123"}}
      env = ClaudeCode.build_env(config)

      assert {~c"ANTHROPIC_API_KEY", ~c"sk-test-123"} in env
      refute Enum.any?(env, fn {k, _} -> k == ~c"CLAUDE_CODE_OAUTH_TOKEN" end)
    end

    test "sets ANTHROPIC_API_KEY for default (nil) auth mode" do
      config = %{"agent" => %{"api_key" => "sk-test-456"}}
      env = ClaudeCode.build_env(config)

      assert {~c"ANTHROPIC_API_KEY", ~c"sk-test-456"} in env
    end

    test "sets CLAUDE_OAUTH_TOKEN for oauth auth mode" do
      config = %{"agent" => %{"auth_mode" => "oauth", "oauth_token" => "oauth-abc"}}
      env = ClaudeCode.build_env(config)

      assert {~c"CLAUDE_CODE_OAUTH_TOKEN", ~c"oauth-abc"} in env
      refute Enum.any?(env, fn {k, _} -> k == ~c"ANTHROPIC_API_KEY" end)
    end

    test "returns empty list for oauth mode without token" do
      config = %{"agent" => %{"auth_mode" => "oauth"}}
      env = ClaudeCode.build_env(config)

      assert env == []
    end

    test "includes GITHUB_TOKEN from tracker api_key (PAT mode)" do
      config = %{
        "agent" => %{"api_key" => "sk-test"},
        "tracker" => %{"api_key" => "ghp_pat_token"}
      }

      env = ClaudeCode.build_env(config)
      assert {~c"GITHUB_TOKEN", ~c"ghp_pat_token"} in env
      assert {~c"ANTHROPIC_API_KEY", ~c"sk-test"} in env
    end

    test "includes GITHUB_TOKEN from GITHUB_TOKEN env var when no tracker api_key" do
      config = %{"agent" => %{"api_key" => "sk-test"}, "tracker" => %{}}
      System.put_env("GITHUB_TOKEN", "ghp_env_token")

      env = ClaudeCode.build_env(config)
      assert {~c"GITHUB_TOKEN", ~c"ghp_env_token"} in env

      System.delete_env("GITHUB_TOKEN")
    end

    test "omits GITHUB_TOKEN when neither tracker api_key nor env var set" do
      config = %{"agent" => %{"api_key" => "sk-test"}, "tracker" => %{}}
      System.delete_env("GITHUB_TOKEN")

      env = ClaudeCode.build_env(config)
      refute Enum.any?(env, fn {k, _} -> k == ~c"GITHUB_TOKEN" end)
    end
  end

  describe "parse_event/1" do
    test "parses assistant event" do
      json =
        Jason.encode!(%{
          "type" => "assistant",
          "message" => "I'll fix this bug.",
          "session_id" => "sess_123",
          "usage" => %{"input_tokens" => 100, "output_tokens" => 50}
        })

      assert {:ok, %Event{} = event} = ClaudeCode.parse_event(json)
      assert event.type == "assistant"
      assert event.session_id == "sess_123"
      assert event.message == "I'll fix this bug."
      assert event.input_tokens == 100
      assert event.output_tokens == 50
      assert event.total_tokens == 150
    end

    test "parses result event" do
      json =
        Jason.encode!(%{
          "type" => "result",
          "result" => "Task completed successfully.",
          "usage" => %{"input_tokens" => 200, "output_tokens" => 100}
        })

      assert {:ok, %Event{} = event} = ClaudeCode.parse_event(json)
      assert event.type == "result"
      assert event.message == "Task completed successfully."
    end

    test "extracts session_id from metadata" do
      json =
        Jason.encode!(%{
          "type" => "system",
          "metadata" => %{"session_id" => "sess_456"}
        })

      assert {:ok, event} = ClaudeCode.parse_event(json)
      assert event.session_id == "sess_456"
    end

    test "skips non-JSON lines" do
      assert :skip = ClaudeCode.parse_event("not json")
      assert :skip = ClaudeCode.parse_event("")
    end

    test "handles missing usage gracefully" do
      json = Jason.encode!(%{"type" => "system"})
      assert {:ok, event} = ClaudeCode.parse_event(json)
      assert event.input_tokens == 0
      assert event.output_tokens == 0
      assert event.total_tokens == 0
    end
  end
end
