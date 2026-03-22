defmodule Synkade.Prompt.RendererTest do
  use ExUnit.Case, async: true

  alias Synkade.Prompt.Renderer

  @project %{name: "api", config: %{}}
  @issue %{
    project_name: "api",
    id: "123",
    identifier: "acme/api#123",
    title: "Fix the login bug",
    body: "The login form crashes on empty email.",
    state: "open",
    labels: ["bug", "urgent"],
    blocked_by: [%{id: "100", identifier: "acme/api#100", state: "open"}],
    priority: nil,
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

    test "handles body" do
      template = "{{ issue.body }}"
      assert {:ok, rendered} = Renderer.render(template, @project, @issue)
      assert rendered =~ "The login form crashes on empty email."
    end

    test "uses default template when nil" do
      assert {:ok, rendered} = Renderer.render(nil, @project, @issue)
      assert rendered =~ "acme/api#123"
      assert rendered =~ "Fix the login bug"
      assert rendered =~ "The login form crashes on empty email."
      assert rendered =~ "implement the fix"
      assert rendered =~ "synkade skill"
    end

    test "returns error for invalid template syntax" do
      template = "{% invalid_tag %}"
      assert {:error, {:template_parse_error, _}} = Renderer.render(template, @project, @issue)
    end
  end

  describe "render/6 with auto_merge" do
    test "includes auto-merge line when enabled" do
      issue = Map.put(@issue, :auto_merge, true)
      assert {:ok, rendered} = Renderer.render(nil, @project, issue)
      assert rendered =~ "gh pr merge --merge"
    end

    test "omits auto-merge line when not enabled" do
      assert {:ok, rendered} = Renderer.render(nil, @project, @issue)
      refute rendered =~ "gh pr merge --merge"
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
