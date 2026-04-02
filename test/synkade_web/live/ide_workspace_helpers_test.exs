defmodule SynkadeWeb.IdeWorkspaceHelpersTest do
  use ExUnit.Case, async: true

  alias SynkadeWeb.IdeWorkspaceHelpers

  describe "detect_branches/1" do
    test "returns defaults for nil path" do
      assert IdeWorkspaceHelpers.detect_branches(nil) == {"HEAD", nil}
    end

    test "returns defaults for non-existent path" do
      assert IdeWorkspaceHelpers.detect_branches("/nonexistent/path") == {"HEAD", nil}
    end
  end

  describe "load_commits_ahead/2" do
    test "returns 0 for nil path" do
      assert IdeWorkspaceHelpers.load_commits_ahead(nil, "main") == 0
    end

    test "returns 0 for non-existent path" do
      assert IdeWorkspaceHelpers.load_commits_ahead("/nonexistent", "main") == 0
    end
  end

  describe "load_changed_files/2" do
    test "returns empty list for nil path" do
      assert IdeWorkspaceHelpers.load_changed_files(nil, "main") == []
    end

    test "returns empty list for non-existent path" do
      assert IdeWorkspaceHelpers.load_changed_files("/nonexistent", "main") == []
    end
  end

  describe "load_file_diff/3" do
    test "returns empty list for nil path" do
      assert IdeWorkspaceHelpers.load_file_diff(nil, "file.ex", "main") == []
    end
  end

  describe "current_head_sha/1" do
    test "returns nil for nil path" do
      assert IdeWorkspaceHelpers.current_head_sha(nil) == nil
    end

    test "returns nil for non-existent path" do
      assert IdeWorkspaceHelpers.current_head_sha("/nonexistent") == nil
    end
  end

  describe "compute_turn_files/2" do
    test "returns empty list when start_sha is nil" do
      assert IdeWorkspaceHelpers.compute_turn_files("/some/path", nil) == []
    end
  end
end
