defmodule Synkade.Execution.SpritesTest do
  use ExUnit.Case, async: true

  alias Synkade.Execution.Sprites

  describe "sanitize_sprite_name/1" do
    test "lowercases and replaces invalid chars" do
      assert Sprites.sanitize_sprite_name("MyProject_Issue#42") == "myproject-issue-42"
    end

    test "collapses consecutive hyphens" do
      assert Sprites.sanitize_sprite_name("foo---bar") == "foo-bar"
    end

    test "trims leading and trailing hyphens" do
      assert Sprites.sanitize_sprite_name("-foo-bar-") == "foo-bar"
    end

    test "truncates to 63 characters" do
      long_name = String.duplicate("a", 100)
      result = Sprites.sanitize_sprite_name(long_name)
      assert String.length(result) == 63
    end

    test "handles per-user naming pattern" do
      result = Sprites.sanitize_sprite_name("synkade-u12345")
      assert result == "synkade-u12345"
    end

    test "handles user ID with UUID format" do
      result = Sprites.sanitize_sprite_name("synkade-uabc123-def456")
      assert result == "synkade-uabc123-def456"
    end

    test "handles special characters" do
      result = Sprites.sanitize_sprite_name("synkade-u@special!")
      assert result == "synkade-u-special"
    end
  end

  describe "sanitize_path_segment/1" do
    test "lowercases and replaces invalid chars" do
      assert Sprites.sanitize_path_segment("My-Project#1") == "my-project-1"
    end

    test "preserves dots and underscores" do
      assert Sprites.sanitize_path_segment("my.project_v2") == "my.project_v2"
    end

    test "collapses consecutive hyphens" do
      assert Sprites.sanitize_path_segment("foo---bar") == "foo-bar"
    end

    test "trims leading and trailing hyphens" do
      assert Sprites.sanitize_path_segment("-foo-bar-") == "foo-bar"
    end
  end

  describe "build_bare_repo_path/1" do
    test "builds path from project name" do
      assert Sprites.build_bare_repo_path("my-project") == "/repos/my-project.git"
    end

    test "sanitizes project name" do
      assert Sprites.build_bare_repo_path("My Project!") == "/repos/my-project.git"
    end
  end

  describe "build_worktree_path/2" do
    test "builds path from project and issue" do
      assert Sprites.build_worktree_path("my-project", "issue-42") ==
               "/workspaces/my-project/issue-42"
    end

    test "sanitizes both segments" do
      assert Sprites.build_worktree_path("My Project", "Issue #42") ==
               "/workspaces/my-project/issue-42"
    end
  end

  describe "build_env_list/1" do
    test "converts charlist env vars to string tuple list" do
      config = %{
        "agent" => %{
          "auth_mode" => "api_key",
          "api_key" => "sk-test-123"
        }
      }

      result = Sprites.build_env_list(config)
      assert is_list(result)
      assert {"ANTHROPIC_API_KEY", "sk-test-123"} in result
    end

    test "returns empty list when no env vars configured" do
      config = %{"agent" => %{"auth_mode" => "api_key", "api_key" => nil}}
      result = Sprites.build_env_list(config)
      assert result == []
    end

    test "handles oauth token" do
      config = %{
        "agent" => %{
          "auth_mode" => "oauth",
          "oauth_token" => "oauth-token-123"
        }
      }

      result = Sprites.build_env_list(config)
      assert {"CLAUDE_CODE_OAUTH_TOKEN", "oauth-token-123"} in result
    end
  end

  describe "await_event/2" do
    test "receives sprites stdout format" do
      # Use a struct-like map that matches the Sprites.Command pattern
      cmd = %{ref: make_ref(), pid: self(), sprite: nil, owner: self(), tty_mode: false}

      session = %{
        session_id: nil,
        env_ref: nil,
        events: [],
        backend_data: %{command: cmd},
        agent_session: nil
      }

      # Send a sprites-format message to self
      send(self(), {:stdout, cmd, ~s({"type":"assistant","message":"hello"})})

      assert {:data, data} = Sprites.await_event(session, 5_000)
      assert data == ~s({"type":"assistant","message":"hello"})
    end

    test "receives sprites exit format" do
      cmd = %{ref: make_ref(), pid: self(), sprite: nil, owner: self(), tty_mode: false}

      session = %{
        session_id: nil,
        env_ref: nil,
        events: [],
        backend_data: %{command: cmd},
        agent_session: nil
      }

      send(self(), {:exit, cmd, 0})

      assert {:exit, 0} = Sprites.await_event(session, 5_000)
    end

    test "returns timeout when no messages" do
      cmd = %{ref: make_ref(), pid: self(), sprite: nil, owner: self(), tty_mode: false}

      session = %{
        session_id: nil,
        env_ref: nil,
        events: [],
        backend_data: %{command: cmd},
        agent_session: nil
      }

      assert :timeout = Sprites.await_event(session, 10)
    end

    test "ignores messages for other commands" do
      cmd = %{ref: make_ref(), pid: self(), sprite: nil, owner: self(), tty_mode: false}
      other_cmd = %{ref: make_ref(), pid: self(), sprite: nil, owner: self(), tty_mode: false}

      session = %{
        session_id: nil,
        env_ref: nil,
        events: [],
        backend_data: %{command: cmd},
        agent_session: nil
      }

      send(self(), {:stdout, other_cmd, "wrong command"})

      assert :timeout = Sprites.await_event(session, 50)
    end
  end

  describe "parse_event/2" do
    test "delegates to agent adapter parse_event" do
      config = %{"agent" => %{"kind" => "claude"}}
      line = Jason.encode!(%{"type" => "result", "result" => "done"})
      assert {:ok, event} = Sprites.parse_event(config, line)
      assert event.type == "result"
    end

    test "skips invalid JSON" do
      config = %{"agent" => %{"kind" => "claude"}}
      assert :skip = Sprites.parse_event(config, "not json")
    end
  end
end
