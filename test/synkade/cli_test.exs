defmodule Synkade.CLITest do
  use ExUnit.Case, async: true

  alias Synkade.CLI

  describe "parse_args/1" do
    test "parses workflow path" do
      CLI.parse_args(["my_workflow.md"])
      assert Application.get_env(:synkade, :workflow_path) == "my_workflow.md"
    after
      Application.delete_env(:synkade, :workflow_path)
    end

    test "parses --port flag" do
      CLI.parse_args(["--port", "5000"])
      config = Application.get_env(:synkade, SynkadeWeb.Endpoint)
      assert config[:http] == [port: 5000]
    after
      Application.delete_env(:synkade, SynkadeWeb.Endpoint)
    end

    test "parses both path and port" do
      CLI.parse_args(["my_workflow.md", "--port", "8080"])
      assert Application.get_env(:synkade, :workflow_path) == "my_workflow.md"
    after
      Application.delete_env(:synkade, :workflow_path)
      Application.delete_env(:synkade, SynkadeWeb.Endpoint)
    end

    test "handles empty args" do
      assert :ok = CLI.parse_args([])
    end
  end
end
