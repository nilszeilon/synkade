defmodule Synkade.Workflow.LoaderTest do
  use ExUnit.Case, async: true

  alias Synkade.Workflow.Loader

  describe "parse/1" do
    test "parses valid YAML front matter and prompt body" do
      content = """
      ---
      tracker:
        kind: github
        repo: acme/api
      agent:
        max_turns: 5
      ---

      You are working on {{ issue.identifier }}.
      """

      assert {:ok, workflow} = Loader.parse(content)
      assert workflow.config["tracker"]["kind"] == "github"
      assert workflow.config["tracker"]["repo"] == "acme/api"
      assert workflow.config["agent"]["max_turns"] == 5
      assert workflow.prompt_template =~ "You are working on"
    end

    test "returns empty config when no front matter" do
      content = "Just a prompt body with no YAML."
      assert {:ok, workflow} = Loader.parse(content)
      assert workflow.config == %{}
      assert workflow.prompt_template == "Just a prompt body with no YAML."
    end

    test "trims prompt body" do
      content = """
      ---
      tracker:
        kind: github
      ---

        Hello world

      """

      assert {:ok, workflow} = Loader.parse(content)
      assert workflow.prompt_template == "Hello world"
    end

    test "handles empty front matter" do
      content = """
      ---
      ---

      Prompt only.
      """

      assert {:ok, workflow} = Loader.parse(content)
      assert workflow.config == %{}
      assert workflow.prompt_template == "Prompt only."
    end

    test "returns error for non-map YAML" do
      content = """
      ---
      - item1
      - item2
      ---

      Prompt.
      """

      assert {:error, :workflow_front_matter_not_a_map} = Loader.parse(content)
    end

    test "returns error for invalid YAML" do
      content = """
      ---
      {invalid: yaml: [broken
      ---

      Prompt.
      """

      assert {:error, {:workflow_parse_error, _reason}} = Loader.parse(content)
    end
  end

  describe "load/1" do
    test "returns error for missing file" do
      assert {:error, :missing_workflow_file} = Loader.load("/nonexistent/WORKFLOW.md")
    end

    test "loads a valid file" do
      path = Path.join(System.tmp_dir!(), "test_workflow_#{:rand.uniform(100_000)}.md")

      try do
        File.write!(path, """
        ---
        tracker:
          kind: github
          repo: test/repo
        ---

        Work on {{ issue.title }}.
        """)

        assert {:ok, workflow} = Loader.load(path)
        assert workflow.config["tracker"]["repo"] == "test/repo"
      after
        File.rm(path)
      end
    end
  end
end
