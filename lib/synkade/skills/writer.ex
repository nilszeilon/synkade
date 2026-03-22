defmodule Synkade.Skills.Writer do
  @moduledoc false

  # Maps agent kind → the skills directory prefix used by that agent.
  # Both Claude Code and OpenCode follow the Agent Skills open standard
  # (SKILL.md with YAML frontmatter) but each has its own native path.
  @skills_root %{
    "claude" => ".claude/skills",
    "opencode" => ".opencode/skills",
    "codex" => ".agents/skills"
  }

  @doc """
  Returns a list of `{relative_path, content}` tuples for skill files
  that should be written into the agent's workspace.
  """
  def skill_files(config, agent_skills) do
    kind = Synkade.Workflow.Config.agent_kind(config)
    prefix = Map.get(@skills_root, kind)

    if prefix do
      project_id = config["project_id"] || ""

      Enum.map(agent_skills || [], fn skill ->
        content = String.replace(skill["content"], "PROJECT_ID", project_id)
        path = "#{prefix}/#{skill["name"]}/SKILL.md"
        {path, content}
      end)
    else
      []
    end
  end

  @doc """
  Writes skill files into a local workspace directory.
  """
  def write_to_workspace(workspace_path, config, agent_skills) do
    for {relative_path, content} <- skill_files(config, agent_skills) do
      full_path = Path.join(workspace_path, relative_path)
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, content)
    end

    :ok
  end
end
