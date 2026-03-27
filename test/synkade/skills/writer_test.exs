defmodule Synkade.Skills.WriterTest do
  use ExUnit.Case, async: true

  alias Synkade.Skills.Writer

  @default_skills Synkade.Skills.defaults()

  describe "skill_files/2 for claude agent" do
    test "returns .claude/skills/ paths for claude kind" do
      config = %{"agent" => %{"kind" => "claude"}, "project_id" => "proj-123"}
      files = Writer.skill_files(config, @default_skills)

      assert length(files) > 0

      for {path, _content} <- files do
        assert String.starts_with?(path, ".claude/skills/")
        assert String.ends_with?(path, "/SKILL.md")
      end
    end

    test "templates PROJECT_ID with project_id from config" do
      config = %{"agent" => %{"kind" => "claude"}, "project_id" => "abc-def-123"}
      files = Writer.skill_files(config, @default_skills)

      for {_path, content} <- files do
        refute String.contains?(content, "PROJECT_ID")
        assert String.contains?(content, "abc-def-123")
      end
    end

    test "includes default skills when passed" do
      config = %{"agent" => %{"kind" => "claude"}, "project_id" => "p1"}
      files = Writer.skill_files(config, @default_skills)
      paths = Enum.map(files, &elem(&1, 0))

      assert ".claude/skills/synkade/SKILL.md" in paths
    end

    test "returns empty list when no skills provided" do
      config = %{"agent" => %{"kind" => "claude"}, "project_id" => "p1"}
      files = Writer.skill_files(config, [])
      assert files == []
    end

    test "user skill is written correctly" do
      config = %{"agent" => %{"kind" => "claude"}, "project_id" => "p1"}

      user_skills = [
        %{"name" => "my-custom-skill", "content" => "do something"}
      ]

      files = Writer.skill_files(config, user_skills)
      paths = Enum.map(files, &elem(&1, 0))

      assert ".claude/skills/my-custom-skill/SKILL.md" in paths
    end

    test "user skill with same name as default uses user content" do
      config = %{"agent" => %{"kind" => "claude"}, "project_id" => "p1"}

      user_skills = [
        %{"name" => "synkade", "content" => "custom content"}
      ]

      files = Writer.skill_files(config, user_skills)
      {_path, content} = Enum.find(files, fn {p, _} -> String.contains?(p, "synkade") end)

      assert content == "custom content"
    end
  end

  describe "skill_files/2 for opencode agent" do
    test "uses .opencode/skills/ native path" do
      config = %{"agent" => %{"kind" => "opencode"}, "project_id" => "p1"}
      files = Writer.skill_files(config, @default_skills)

      assert length(files) > 0

      for {path, _content} <- files do
        assert String.starts_with?(path, ".opencode/skills/")
        assert String.ends_with?(path, "/SKILL.md")
      end
    end

    test "keeps YAML frontmatter (OpenCode understands SKILL.md format)" do
      config = %{"agent" => %{"kind" => "opencode"}, "project_id" => "p1"}
      files = Writer.skill_files(config, @default_skills)

      for {_path, content} <- files do
        assert String.contains?(content, "---")
        assert String.contains?(content, "name:")
      end
    end
  end

  describe "skill_files/2 for codex agent" do
    test "uses .agents/skills/ native path" do
      config = %{"agent" => %{"kind" => "codex"}, "project_id" => "p1"}
      files = Writer.skill_files(config, @default_skills)

      assert length(files) > 0

      for {path, _content} <- files do
        assert String.starts_with?(path, ".agents/skills/")
        assert String.ends_with?(path, "/SKILL.md")
      end
    end
  end

  describe "skill_files/2 for unknown agent kind" do
    test "returns empty list for unsupported kinds" do
      config = %{"agent" => %{"kind" => "hermes"}, "project_id" => "p1"}
      assert Writer.skill_files(config, []) == []
    end
  end

  describe "write_to_workspace/3" do
    test "writes skill files to workspace directory" do
      workspace =
        System.tmp_dir!() |> Path.join("skills_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(workspace)

      config = %{"agent" => %{"kind" => "claude"}, "project_id" => "test-proj"}

      try do
        Writer.write_to_workspace(workspace, config, @default_skills)

        skill_path = Path.join(workspace, ".claude/skills/synkade/SKILL.md")
        assert File.exists?(skill_path)

        content = File.read!(skill_path)
        assert String.contains?(content, "test-proj")
        refute String.contains?(content, "PROJECT_ID")
      after
        File.rm_rf!(workspace)
      end
    end
  end
end
