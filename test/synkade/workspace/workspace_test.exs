defmodule Synkade.Workspace.WorkspaceTest do
  use ExUnit.Case, async: true

  alias Synkade.Workspace.{Manager, Safety, Hooks}

  describe "Safety.sanitize_key/1" do
    test "sanitizes owner/repo#123 format" do
      assert Safety.sanitize_key("acme/api#123") == "acme/api_123"
    end

    test "preserves valid characters" do
      assert Safety.sanitize_key("my-project/issue_42") == "my-project/issue_42"
    end

    test "replaces spaces and special chars" do
      assert Safety.sanitize_key("my project@v2!") == "my_project_v2_"
    end
  end

  describe "Safety.validate_path_containment/2" do
    test "allows path under root" do
      assert :ok = Safety.validate_path_containment("/tmp/ws/project/issue", "/tmp/ws")
    end

    test "rejects path outside root" do
      assert {:error, _} = Safety.validate_path_containment("/etc/passwd", "/tmp/ws")
    end

    test "rejects path traversal" do
      assert {:error, _} = Safety.validate_path_containment("/tmp/ws/../etc/passwd", "/tmp/ws")
    end
  end

  describe "Safety.validate_key/1" do
    test "accepts valid key" do
      assert :ok = Safety.validate_key("my-project/issue_42")
    end

    test "rejects invalid characters" do
      assert {:error, _} = Safety.validate_key("my project#42")
    end
  end

  describe "Hooks.run_hook/3" do
    @tag :tmp_dir
    test "runs hook script successfully", %{tmp_dir: dir} do
      assert :ok = Hooks.run_hook("echo hello", dir)
    end

    @tag :tmp_dir
    test "returns nil script as ok", %{tmp_dir: dir} do
      assert :ok = Hooks.run_hook(nil, dir)
    end

    @tag :tmp_dir
    test "returns error on non-zero exit", %{tmp_dir: dir} do
      assert {:error, msg} = Hooks.run_hook("exit 1", dir)
      assert msg =~ "exited with code 1"
    end

    @tag :tmp_dir
    test "respects timeout", %{tmp_dir: dir} do
      # Very short timeout should fail
      assert {:error, _} = Hooks.run_hook("sleep 10", dir, timeout_ms: 100)
    end
  end

  describe "Manager.ensure_workspace/3" do
    @tag :tmp_dir
    test "creates workspace directory", %{tmp_dir: dir} do
      config = %{"workspace" => %{"root" => dir}}

      assert {:ok, ws} = Manager.ensure_workspace(config, "api", "acme/api#42")
      assert ws.project_name == "api"
      assert ws.workspace_key == "api/acme/api_42"
      assert File.dir?(ws.path)
    end

    @tag :tmp_dir
    test "reuses existing workspace", %{tmp_dir: dir} do
      config = %{"workspace" => %{"root" => dir}}

      assert {:ok, ws1} = Manager.ensure_workspace(config, "api", "acme/api#42")

      assert {:ok, ws2} = Manager.ensure_workspace(config, "api", "acme/api#42")
      assert ws2.path == ws1.path
    end

    @tag :tmp_dir
    test "runs after_create hook on new workspace", %{tmp_dir: dir} do
      config = %{
        "workspace" => %{"root" => dir},
        "hooks" => %{"after_create" => "touch hook_ran.txt"}
      }

      assert {:ok, ws} = Manager.ensure_workspace(config, "api", "issue_1")
      assert File.exists?(Path.join(ws.path, "hook_ran.txt"))
    end

    @tag :tmp_dir
    test "aborts workspace on after_create hook failure", %{tmp_dir: dir} do
      config = %{
        "workspace" => %{"root" => dir},
        "hooks" => %{"after_create" => "exit 1"}
      }

      assert {:error, {:hook_failed, :after_create, _}} =
               Manager.ensure_workspace(config, "api", "issue_2")

      refute File.dir?(Path.join(dir, "api/issue_2"))
    end

    @tag :tmp_dir
    test "creates git worktree when repo is configured", %{tmp_dir: dir} do
      # Set up a local "remote" repo to clone from
      origin = Path.join(dir, "origin_repo")
      File.mkdir_p!(origin)
      System.cmd("git", ["init", "-b", "main"], cd: origin)
      System.cmd("git", ["config", "user.email", "test@test.com"], cd: origin)
      System.cmd("git", ["config", "user.name", "Test"], cd: origin)
      File.write!(Path.join(origin, "README.md"), "# Hello\n")
      System.cmd("git", ["add", "."], cd: origin)
      System.cmd("git", ["commit", "-m", "init"], cd: origin)

      ws_root = Path.join(dir, "workspaces")
      File.mkdir_p!(ws_root)

      config = %{
        "workspace" => %{"root" => ws_root},
        "tracker" => %{"repo" => origin}
      }

      assert {:ok, ws} = Manager.ensure_workspace(config, "myapp", "myapp#abc12345")
      assert File.dir?(ws.path)
      # Should have the cloned file
      assert File.exists?(Path.join(ws.path, "README.md"))
      # Should be on a synkade/* branch
      {branch, 0} = System.cmd("git", ["branch", "--show-current"], cd: ws.path)
      assert String.trim(branch) =~ "synkade/"
      # Main repo should exist separately
      main_repo = Manager.main_repo_path(ws_root, "myapp")
      assert File.dir?(Path.join(main_repo, ".git"))
    end

    @tag :tmp_dir
    test "second issue gets its own worktree from same repo", %{tmp_dir: dir} do
      origin = Path.join(dir, "origin_repo")
      File.mkdir_p!(origin)
      System.cmd("git", ["init", "-b", "main"], cd: origin)
      System.cmd("git", ["config", "user.email", "test@test.com"], cd: origin)
      System.cmd("git", ["config", "user.name", "Test"], cd: origin)
      File.write!(Path.join(origin, "README.md"), "# Hello\n")
      System.cmd("git", ["add", "."], cd: origin)
      System.cmd("git", ["commit", "-m", "init"], cd: origin)

      ws_root = Path.join(dir, "workspaces")
      File.mkdir_p!(ws_root)

      config = %{
        "workspace" => %{"root" => ws_root},
        "tracker" => %{"repo" => origin}
      }

      assert {:ok, ws1} = Manager.ensure_workspace(config, "myapp", "myapp#issue1")
      assert {:ok, ws2} = Manager.ensure_workspace(config, "myapp", "myapp#issue2")

      # Different paths
      assert ws1.path != ws2.path
      # Both have the file
      assert File.exists?(Path.join(ws1.path, "README.md"))
      assert File.exists?(Path.join(ws2.path, "README.md"))
      # Different branches
      {b1, 0} = System.cmd("git", ["branch", "--show-current"], cd: ws1.path)
      {b2, 0} = System.cmd("git", ["branch", "--show-current"], cd: ws2.path)
      assert String.trim(b1) != String.trim(b2)
    end
  end

end
