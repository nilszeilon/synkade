defmodule Synkade.Agent.OpenClawTest do
  use ExUnit.Case, async: true

  alias Synkade.Agent.OpenClaw
  alias Synkade.Agent.Event

  describe "fetch_models/1" do
    test "returns curated model list" do
      assert {:ok, models} = OpenClaw.fetch_models("unused")
      assert is_list(models)
      assert length(models) > 0
      assert Enum.all?(models, fn {label, id} -> is_binary(label) and is_binary(id) end)
    end
  end

  describe "build_args/3" do
    test "builds default args with prompt" do
      config = %{}
      args = OpenClaw.build_args(config, "Fix the bug", [])

      assert "agent" in args
      assert "--message" in args
      assert "Fix the bug" in args
      assert "--format" in args
      assert "json" in args
      assert "--local" in args
    end

    test "includes model when specified" do
      config = %{"agent" => %{"model" => "anthropic/claude-sonnet-4-20250514"}}
      args = OpenClaw.build_args(config, "prompt", [])

      idx = Enum.find_index(args, &(&1 == "--model"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "anthropic/claude-sonnet-4-20250514"
    end

    test "includes --continue for continuation" do
      config = %{}
      args = OpenClaw.build_args(config, "continue", ["--continue"])

      assert "--continue" in args
    end

    test "does not include model when not specified" do
      config = %{}
      args = OpenClaw.build_args(config, "prompt", [])

      refute "--model" in args
    end
  end

  describe "build_env/1" do
    test "sets ANTHROPIC_API_KEY from api_key" do
      config = %{"agent" => %{"api_key" => "sk-ant-test-123"}}
      env = OpenClaw.build_env(config)

      assert {~c"ANTHROPIC_API_KEY", ~c"sk-ant-test-123"} in env
    end

    test "returns empty agent env when no api_key" do
      config = %{"agent" => %{}}
      System.delete_env("GITHUB_TOKEN")
      env = OpenClaw.build_env(config)

      refute Enum.any?(env, fn {k, _} -> k == ~c"ANTHROPIC_API_KEY" end)
    end

    test "returns empty agent env when api_key is empty string" do
      config = %{"agent" => %{"api_key" => ""}}
      System.delete_env("GITHUB_TOKEN")
      env = OpenClaw.build_env(config)

      refute Enum.any?(env, fn {k, _} -> k == ~c"ANTHROPIC_API_KEY" end)
    end

    test "includes GITHUB_TOKEN from tracker api_key" do
      config = %{
        "agent" => %{"api_key" => "sk-ant-test"},
        "tracker" => %{"api_key" => "ghp_pat_token"}
      }

      env = OpenClaw.build_env(config)
      assert {~c"GITHUB_TOKEN", ~c"ghp_pat_token"} in env
    end

    test "includes SYNKADE_API_URL and SYNKADE_API_TOKEN" do
      config = %{
        "agent" => %{
          "api_key" => "sk-ant-test",
          "synkade_api_url" => "http://localhost:4000",
          "synkade_api_token" => "tok_abc"
        }
      }

      env = OpenClaw.build_env(config)
      assert {~c"SYNKADE_API_URL", ~c"http://localhost:4000"} in env
      assert {~c"SYNKADE_API_TOKEN", ~c"tok_abc"} in env
    end
  end

  describe "parse_event/1" do
    test "parses assistant event" do
      json =
        Jason.encode!(%{
          "type" => "assistant",
          "message" => "I'll fix this.",
          "session_id" => "sess_123",
          "usage" => %{"input_tokens" => 100, "output_tokens" => 50}
        })

      assert {:ok, %Event{} = event} = OpenClaw.parse_event(json)
      assert event.type == "assistant"
      assert event.session_id == "sess_123"
      assert event.message == "I'll fix this."
      assert event.input_tokens == 100
      assert event.output_tokens == 50
      assert event.total_tokens == 150
    end

    test "parses text event with part.text" do
      json =
        Jason.encode!(%{
          "type" => "text",
          "session_id" => "sess_123",
          "part" => %{"text" => "Hello world"}
        })

      assert {:ok, %Event{} = event} = OpenClaw.parse_event(json)
      assert event.type == "text"
      assert event.message == "Hello world"
    end

    test "parses result event" do
      json =
        Jason.encode!(%{
          "type" => "result",
          "result" => "Task completed.",
          "usage" => %{"input_tokens" => 200, "output_tokens" => 100}
        })

      assert {:ok, %Event{} = event} = OpenClaw.parse_event(json)
      assert event.type == "result"
      assert event.message == "Task completed."
    end

    test "parses error event" do
      json =
        Jason.encode!(%{
          "type" => "error",
          "error" => %{"message" => "Rate limited"}
        })

      assert {:ok, %Event{} = event} = OpenClaw.parse_event(json)
      assert event.type == "error"
      assert event.message == "Rate limited"
    end

    test "skips non-JSON lines" do
      assert :skip = OpenClaw.parse_event("not json")
      assert :skip = OpenClaw.parse_event("")
    end

    test "handles missing usage gracefully" do
      json = Jason.encode!(%{"type" => "system"})
      assert {:ok, event} = OpenClaw.parse_event(json)
      assert event.input_tokens == 0
      assert event.output_tokens == 0
      assert event.total_tokens == 0
    end
  end
end
