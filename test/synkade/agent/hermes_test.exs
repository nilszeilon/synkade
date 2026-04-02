defmodule Synkade.Agent.HermesTest do
  use ExUnit.Case, async: true

  alias Synkade.Agent.Hermes
  alias Synkade.Agent.Event

  describe "fetch_models/1" do
    @tag :external
    test "fetches models from OpenRouter" do
      assert {:ok, models} = Hermes.fetch_models(nil)
      assert is_list(models)
      assert length(models) > 0
      assert Enum.all?(models, fn {label, id} -> is_binary(label) and is_binary(id) end)
    end
  end

  describe "build_args/3" do
    test "builds default args with prompt" do
      config = %{}
      args = Hermes.build_args(config, "Fix the bug", [])

      assert "chat" in args
      assert "-q" in args
      assert "Fix the bug" in args
      assert "--quiet" in args
    end

    test "includes model when specified" do
      config = %{"agent" => %{"model" => "anthropic/claude-sonnet-4-20250514"}}
      args = Hermes.build_args(config, "prompt", [])

      idx = Enum.find_index(args, &(&1 == "--model"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "anthropic/claude-sonnet-4-20250514"
    end

    test "includes resume flag for continuation" do
      config = %{}
      args = Hermes.build_args(config, "continue", ["--resume", "session_abc"])

      assert "--resume" in args
      assert "session_abc" in args
    end

    test "does not include model when not specified" do
      config = %{}
      args = Hermes.build_args(config, "prompt", [])

      refute "--model" in args
    end
  end

  describe "build_env/1" do
    test "sets OPENROUTER_API_KEY from api_key" do
      config = %{"agent" => %{"api_key" => "sk-or-test-123"}}
      env = Hermes.build_env(config)

      assert {~c"OPENROUTER_API_KEY", ~c"sk-or-test-123"} in env
    end

    test "returns empty agent env when no api_key" do
      config = %{"agent" => %{}}
      System.delete_env("GITHUB_TOKEN")
      env = Hermes.build_env(config)

      refute Enum.any?(env, fn {k, _} -> k == ~c"OPENROUTER_API_KEY" end)
    end

    test "returns empty agent env when api_key is empty string" do
      config = %{"agent" => %{"api_key" => ""}}
      System.delete_env("GITHUB_TOKEN")
      env = Hermes.build_env(config)

      refute Enum.any?(env, fn {k, _} -> k == ~c"OPENROUTER_API_KEY" end)
    end

    test "includes GITHUB_TOKEN from tracker api_key" do
      config = %{
        "agent" => %{"api_key" => "sk-or-test"},
        "tracker" => %{"api_key" => "ghp_pat_token"}
      }

      env = Hermes.build_env(config)
      assert {~c"GITHUB_TOKEN", ~c"ghp_pat_token"} in env
    end

    test "includes SYNKADE_API_URL and SYNKADE_API_TOKEN" do
      config = %{
        "agent" => %{
          "api_key" => "sk-or-test",
          "synkade_api_url" => "http://localhost:4000",
          "synkade_api_token" => "tok_abc"
        }
      }

      env = Hermes.build_env(config)
      assert {~c"SYNKADE_API_URL", ~c"http://localhost:4000"} in env
      assert {~c"SYNKADE_API_TOKEN", ~c"tok_abc"} in env
    end
  end

  describe "parse_event/1" do
    test "parses JSON assistant event" do
      json =
        Jason.encode!(%{
          "type" => "assistant",
          "message" => "I'll fix this.",
          "session_id" => "sess_123",
          "usage" => %{"input_tokens" => 100, "output_tokens" => 50}
        })

      assert {:ok, %Event{} = event} = Hermes.parse_event(json)
      assert event.type == "assistant"
      assert event.session_id == "sess_123"
      assert event.message == "I'll fix this."
      assert event.input_tokens == 100
      assert event.output_tokens == 50
      assert event.total_tokens == 150
    end

    test "parses JSON result event" do
      json =
        Jason.encode!(%{
          "type" => "result",
          "result" => "Task completed.",
          "usage" => %{"input_tokens" => 200, "output_tokens" => 100}
        })

      assert {:ok, %Event{} = event} = Hermes.parse_event(json)
      assert event.type == "result"
      assert event.message == "Task completed."
    end

    test "extracts session_id from metadata in JSON" do
      json =
        Jason.encode!(%{
          "type" => "system",
          "metadata" => %{"session_id" => "sess_456"}
        })

      assert {:ok, event} = Hermes.parse_event(json)
      assert event.session_id == "sess_456"
    end

    test "skips empty lines" do
      assert :skip = Hermes.parse_event("")
      assert :skip = Hermes.parse_event("   ")
    end

    test "skips box drawing decorations" do
      assert :skip =
               Hermes.parse_event(
                 "╭─ ⚕ Hermes ───────────────────────────────────────────────────────────────────╮"
               )

      assert :skip =
               Hermes.parse_event(
                 "╰──────────────────────────────────────────────────────────────────────────────╯"
               )
    end

    test "parses tool progress lines" do
      assert {:ok, %Event{type: "tool_use", message: msg}} =
               Hermes.parse_event("  ┊ 🔎 preparing search_files…")

      assert msg =~ "preparing"

      assert {:ok, %Event{type: "tool_result", message: msg}} =
               Hermes.parse_event("  ┊ 💻 $         ls -la  2.8s")

      assert msg =~ "ls -la"
    end

    test "parses session_id line" do
      assert {:ok, %Event{type: "system", session_id: "20260402_212839_2c5034"}} =
               Hermes.parse_event("session_id: 20260402_212839_2c5034")
    end

    test "parses plain text as assistant message" do
      assert {:ok, %Event{type: "assistant", message: "Hello world"}} =
               Hermes.parse_event("Hello world")
    end

    test "handles missing usage gracefully in JSON" do
      json = Jason.encode!(%{"type" => "system"})
      assert {:ok, event} = Hermes.parse_event(json)
      assert event.input_tokens == 0
      assert event.output_tokens == 0
      assert event.total_tokens == 0
    end
  end
end
