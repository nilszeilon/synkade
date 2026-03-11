defmodule Synkade.Prompt.RendererTest do
  use ExUnit.Case, async: true

  alias Synkade.Prompt.Renderer

  @project %{name: "api", config: %{}}
  @issue %{
    project_name: "api",
    id: "123",
    identifier: "acme/api#123",
    title: "Fix the login bug",
    description: "The login form crashes on empty email.",
    state: "open",
    labels: ["bug", "urgent"],
    blocked_by: [%{id: "100", identifier: "acme/api#100", state: "open"}],
    priority: 1,
    url: "https://github.com/acme/api/issues/123"
  }

  describe "render/4" do
    test "interpolates issue variables" do
      template = "Work on {{ issue.identifier }}: {{ issue.title }}"
      assert {:ok, rendered} = Renderer.render(template, @project, @issue)
      assert rendered =~ "Work on acme/api#123: Fix the login bug"
    end

    test "interpolates project variables" do
      template = "Project: {{ project.name }}"
      assert {:ok, rendered} = Renderer.render(template, @project, @issue)
      assert rendered =~ "Project: api"
    end

    test "interpolates attempt variable" do
      template = "Attempt: {{ attempt }}"
      assert {:ok, rendered} = Renderer.render(template, @project, @issue, 2)
      assert rendered =~ "Attempt: 2"
    end

    test "nil attempt renders empty" do
      template = "Attempt: {{ attempt }}"
      assert {:ok, rendered} = Renderer.render(template, @project, @issue, nil)
      assert rendered =~ "Attempt: "
    end

    test "iterates over labels" do
      template = """
      Labels:
      {% for label in issue.labels %}
      - {{ label }}
      {% endfor %}
      """

      assert {:ok, rendered} = Renderer.render(template, @project, @issue)
      assert rendered =~ "- bug"
      assert rendered =~ "- urgent"
    end

    test "iterates over blockers" do
      template = """
      {% for blocker in issue.blocked_by %}
      Blocked by: {{ blocker.identifier }}
      {% endfor %}
      """

      assert {:ok, rendered} = Renderer.render(template, @project, @issue)
      assert rendered =~ "Blocked by: acme/api#100"
    end

    test "handles description" do
      template = "{{ issue.description }}"
      assert {:ok, rendered} = Renderer.render(template, @project, @issue)
      assert rendered =~ "The login form crashes on empty email."
    end

    test "appends PR creation instructions for developer role" do
      template = "Work on {{ issue.identifier }}"
      assert {:ok, rendered} = Renderer.render(template, @project, @issue)
      assert rendered =~ "gh pr create"
      assert rendered =~ "Fix #123"
    end

    test "uses developer default template when nil" do
      assert {:ok, rendered} = Renderer.render(nil, @project, @issue)
      assert rendered =~ "acme/api#123"
      assert rendered =~ "Fix the login bug"
      assert rendered =~ "The login form crashes on empty email."
      assert rendered =~ "gh pr create"
      assert rendered =~ "implement the fix"
    end

    test "returns error for invalid template syntax" do
      template = "{% invalid_tag %}"
      assert {:error, {:template_parse_error, _}} = Renderer.render(template, @project, @issue)
    end
  end

  describe "render/7 with role" do
    test "developer role includes PR suffix" do
      template = "Work on {{ issue.identifier }}"
      assert {:ok, rendered} = Renderer.render(template, @project, @issue, nil, [], nil, "developer")
      assert rendered =~ "gh pr create"
      refute rendered =~ "Do NOT make code changes"
    end

    test "researcher role includes research suffix, no PR suffix" do
      template = "Investigate {{ issue.identifier }}"
      assert {:ok, rendered} = Renderer.render(template, @project, @issue, nil, [], nil, "researcher")
      assert rendered =~ "Do NOT make code changes"
      refute rendered =~ "gh pr create"
    end

    test "researcher default template when nil template" do
      assert {:ok, rendered} = Renderer.render(nil, @project, @issue, nil, [], nil, "researcher")
      assert rendered =~ "investigating"
      assert rendered =~ "Do NOT make code changes"
      refute rendered =~ "gh pr create"
    end

    test "nil role defaults to developer" do
      assert {:ok, rendered} = Renderer.render(nil, @project, @issue, nil, [], nil, nil)
      assert rendered =~ "gh pr create"
      refute rendered =~ "Do NOT make code changes"
    end

    test "both roles include children suffix" do
      assert {:ok, dev_rendered} = Renderer.render(nil, @project, @issue, nil, [], nil, "developer")
      assert {:ok, res_rendered} = Renderer.render(nil, @project, @issue, nil, [], nil, "researcher")
      assert dev_rendered =~ "SYNKADE:CHILDREN"
      assert res_rendered =~ "SYNKADE:CHILDREN"
    end

    test "custom template overrides default but keeps role-appropriate suffix" do
      template = "Custom: {{ issue.title }}"
      assert {:ok, dev} = Renderer.render(template, @project, @issue, nil, [], nil, "developer")
      assert {:ok, res} = Renderer.render(template, @project, @issue, nil, [], nil, "researcher")
      assert dev =~ "Custom: Fix the login bug"
      assert dev =~ "gh pr create"
      assert res =~ "Custom: Fix the login bug"
      assert res =~ "Do NOT make code changes"
    end
  end

  describe "render/6 with dispatch_message" do
    test "includes dispatch message in rendered output" do
      template = "Work on {{ issue.identifier }}"
      assert {:ok, rendered} = Renderer.render(template, @project, @issue, nil, [], "look into X")
      assert rendered =~ "## Human Instructions"
      assert rendered =~ "look into X"
    end

    test "omits dispatch section when nil" do
      template = "Work on {{ issue.identifier }}"
      assert {:ok, rendered} = Renderer.render(template, @project, @issue, nil, [], nil)
      refute rendered =~ "## Human Instructions"
    end

    test "omits dispatch section when not provided" do
      template = "Work on {{ issue.identifier }}"
      assert {:ok, rendered} = Renderer.render(template, @project, @issue, nil, [])
      refute rendered =~ "## Human Instructions"
    end
  end
end
