defmodule Synkade.Execution.LocalTest do
  use ExUnit.Case, async: true

  alias Synkade.Execution.Local

  @moduletag :tmp_dir

  describe "setup_env/3" do
    test "creates workspace directory", %{tmp_dir: tmp_dir} do
      config = %{"workspace" => %{"root" => tmp_dir}}

      assert {:ok, workspace} = Local.setup_env(config, "myproject", "42")
      assert File.dir?(workspace.path)
      assert workspace.project_name == "myproject"
    end
  end

  describe "run_before_hook/2" do
    test "runs hook script successfully", %{tmp_dir: tmp_dir} do
      config = %{
        "workspace" => %{"root" => tmp_dir},
        "hooks" => %{"before_run" => "echo hello", "timeout_ms" => 5_000}
      }

      workspace = %Synkade.Workspace{
        project_name: "test",
        path: tmp_dir,
        workspace_key: "test/1"
      }

      assert :ok = Local.run_before_hook(config, workspace)
    end

    test "returns error on hook failure", %{tmp_dir: tmp_dir} do
      config = %{
        "hooks" => %{"before_run" => "exit 1", "timeout_ms" => 5_000}
      }

      workspace = %Synkade.Workspace{
        project_name: "test",
        path: tmp_dir,
        workspace_key: "test/1"
      }

      assert {:error, {:hook_failed, :before_run, _}} = Local.run_before_hook(config, workspace)
    end

    test "succeeds when no hook configured", %{tmp_dir: tmp_dir} do
      config = %{"hooks" => %{}}

      workspace = %Synkade.Workspace{
        project_name: "test",
        path: tmp_dir,
        workspace_key: "test/1"
      }

      assert :ok = Local.run_before_hook(config, workspace)
    end
  end

  describe "run_after_hook/2" do
    test "always returns :ok even on failure", %{tmp_dir: tmp_dir} do
      config = %{
        "hooks" => %{"after_run" => "exit 1", "timeout_ms" => 5_000}
      }

      workspace = %Synkade.Workspace{
        project_name: "test",
        path: tmp_dir,
        workspace_key: "test/1"
      }

      assert :ok = Local.run_after_hook(config, workspace)
    end
  end

  describe "await_event/2" do
    test "receives port data messages" do
      port = Port.open({:spawn, "echo hello"}, [:binary, :exit_status, {:line, 1_048_576}])

      session = %{
        session_id: nil,
        env_ref: nil,
        events: [],
        backend_data: %{port: port},
        agent_session: nil
      }

      assert {:data, data} = Local.await_event(session, 5_000)
      assert is_binary(data)
    end

    test "receives exit status" do
      port = Port.open({:spawn, "true"}, [:binary, :exit_status, {:line, 1_048_576}])
      # Drain data messages first
      receive do
        {^port, {:data, _}} -> :ok
      after
        100 -> :ok
      end

      session = %{
        session_id: nil,
        env_ref: nil,
        events: [],
        backend_data: %{port: port},
        agent_session: nil
      }

      assert {:exit, 0} = Local.await_event(session, 5_000)
    end

    test "returns timeout when no messages" do
      # Create a port that won't send anything quickly
      port = Port.open({:spawn, "sleep 10"}, [:binary, :exit_status, {:line, 1_048_576}])

      session = %{
        session_id: nil,
        env_ref: nil,
        events: [],
        backend_data: %{port: port},
        agent_session: nil
      }

      assert :timeout = Local.await_event(session, 10)

      # Cleanup
      try do
        Port.close(port)
      catch
        _, _ -> :ok
      end
    end
  end

  describe "parse_event/2" do
    test "parses valid JSON event" do
      config = %{"agent" => %{"kind" => "claude"}}
      line = Jason.encode!(%{"type" => "assistant", "message" => "hello"})
      assert {:ok, event} = Local.parse_event(config, line)
      assert event.type == "assistant"
      assert event.message == "hello"
    end

    test "skips invalid JSON" do
      config = %{"agent" => %{"kind" => "claude"}}
      assert :skip = Local.parse_event(config, "not json")
    end
  end
end
