defmodule Synkade.Workflow.WatcherTest do
  use ExUnit.Case

  alias Synkade.Workflow.Watcher

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    workflow_path = Path.join(tmp_dir, "WORKFLOW.md")

    File.write!(workflow_path, """
    ---
    tracker:
      kind: github
      repo: test/repo
    ---

    Initial prompt.
    """)

    {:ok, workflow_path: workflow_path}
  end

  describe "init and get_workflow" do
    test "loads workflow on init", %{workflow_path: path} do
      pid = start_supervised!({Watcher, path: path, pubsub: Synkade.PubSub, name: :"watcher_#{:rand.uniform(100_000)}"})

      assert {:ok, workflow} = Watcher.get_workflow(pid)
      assert workflow.config["tracker"]["repo"] == "test/repo"
      assert workflow.prompt_template == "Initial prompt."
    end

    test "starts with nil workflow on missing file" do
      pid =
        start_supervised!(
          {Watcher,
           path: "/nonexistent/WORKFLOW.md",
           pubsub: Synkade.PubSub,
           name: :"watcher_missing_#{:rand.uniform(100_000)}"}
        )

      assert {:ok, nil} = Watcher.get_workflow(pid)
    end
  end

  describe "reload" do
    test "reloads workflow on manual reload", %{workflow_path: path} do
      name = :"watcher_reload_#{:rand.uniform(100_000)}"
      pid = start_supervised!({Watcher, path: path, pubsub: Synkade.PubSub, name: name})

      Phoenix.PubSub.subscribe(Synkade.PubSub, Watcher.pubsub_topic())

      File.write!(path, """
      ---
      tracker:
        kind: github
        repo: updated/repo
      ---

      Updated prompt.
      """)

      assert {:ok, workflow} = Watcher.reload(pid)
      assert workflow.config["tracker"]["repo"] == "updated/repo"
      assert workflow.prompt_template == "Updated prompt."

      assert_receive {:workflow_reloaded, ^workflow}, 1000
    end

    test "keeps last-known-good config on invalid reload", %{workflow_path: path} do
      name = :"watcher_invalid_#{:rand.uniform(100_000)}"
      pid = start_supervised!({Watcher, path: path, pubsub: Synkade.PubSub, name: name})

      assert {:ok, original} = Watcher.get_workflow(pid)

      # Write invalid YAML
      File.write!(path, """
      ---
      - invalid list
      ---

      Prompt.
      """)

      assert {:error, :workflow_front_matter_not_a_map} = Watcher.reload(pid)

      # Should still have original workflow
      assert {:ok, ^original} = Watcher.get_workflow(pid)
    end
  end
end
