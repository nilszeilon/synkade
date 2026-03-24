defmodule Synkade.Workspace.GitTest do
  use ExUnit.Case, async: true

  alias Synkade.Workspace.Git

  setup do
    # Create a temp git repo with a main branch
    tmp = Path.join(System.tmp_dir!(), "synkade_git_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp)
    System.cmd("git", ["init", "-b", "main"], cd: tmp)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp)
    System.cmd("git", ["config", "user.name", "Test"], cd: tmp)

    # Create initial commit on main
    File.write!(Path.join(tmp, "README.md"), "# Test\n")
    System.cmd("git", ["add", "."], cd: tmp)
    System.cmd("git", ["commit", "-m", "initial"], cd: tmp)

    on_exit(fn -> File.rm_rf!(tmp) end)
    %{path: tmp}
  end

  test "detect_base_branch finds main", %{path: path} do
    assert Git.detect_base_branch(path) == "main"
  end

  test "current_branch returns branch name", %{path: path} do
    assert Git.current_branch(path) == "main"
  end

  test "changed_files returns empty when on base branch", %{path: path} do
    assert {:ok, []} = Git.changed_files(path, "main")
  end

  test "changed_files shows branch diff against base", %{path: path} do
    # Create a feature branch with changes
    System.cmd("git", ["checkout", "-b", "feature"], cd: path)
    File.write!(Path.join(path, "README.md"), "# Updated\n")
    System.cmd("git", ["add", "."], cd: path)
    System.cmd("git", ["commit", "-m", "update readme"], cd: path)

    assert {:ok, files} = Git.changed_files(path, "main")
    assert [%{status: "M", file: "README.md", additions: add, deletions: del}] = files
    assert add > 0
    assert del > 0
  end

  test "changed_files includes uncommitted changes on branch", %{path: path} do
    System.cmd("git", ["checkout", "-b", "feature"], cd: path)
    # Committed change
    File.write!(Path.join(path, "committed.txt"), "hello\n")
    System.cmd("git", ["add", "."], cd: path)
    System.cmd("git", ["commit", "-m", "add file"], cd: path)
    # Uncommitted change
    File.write!(Path.join(path, "README.md"), "# Changed\n")

    assert {:ok, files} = Git.changed_files(path, "main")
    file_names = Enum.map(files, & &1.file)
    assert "committed.txt" in file_names
    assert "README.md" in file_names
  end

  test "changed_files detects untracked files", %{path: path} do
    System.cmd("git", ["checkout", "-b", "feature"], cd: path)
    File.write!(Path.join(path, "new.txt"), "hello\nworld\n")

    assert {:ok, files} = Git.changed_files(path, "main")
    entry = Enum.find(files, &(&1.file == "new.txt"))
    assert entry.status == "U"
    assert entry.additions > 0
    assert entry.deletions == 0
  end

  test "file_diff returns branch diff for file", %{path: path} do
    System.cmd("git", ["checkout", "-b", "feature"], cd: path)
    File.write!(Path.join(path, "README.md"), "# Updated\n")
    System.cmd("git", ["add", "."], cd: path)
    System.cmd("git", ["commit", "-m", "update"], cd: path)

    assert {:ok, diff} = Git.file_diff(path, "README.md", "main")
    assert diff =~ "+# Updated"
    assert diff =~ "-# Test"
  end

  test "file_diff returns content for untracked file", %{path: path} do
    File.write!(Path.join(path, "new.txt"), "hello\n")
    assert {:ok, diff} = Git.file_diff(path, "new.txt", "main")
    assert diff =~ "+hello"
  end

  test "parse_diff parses unified diff format" do
    raw = """
    --- a/file.txt
    +++ b/file.txt
    @@ -1,3 +1,4 @@
     context line
    -removed line
    +added line
    +another added
     more context
    """

    lines = Git.parse_diff(raw)
    types = Enum.map(lines, & &1.type)

    assert :header in types
    assert :context in types
    assert :add in types
    assert :remove in types
  end

  test "parse_diff returns empty for empty string" do
    assert [] = Git.parse_diff("")
  end

  test "changed_files returns empty for non-git directory" do
    tmp = Path.join(System.tmp_dir!(), "synkade_no_git_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    assert {:ok, []} = Git.changed_files(tmp, "main")
  end
end
