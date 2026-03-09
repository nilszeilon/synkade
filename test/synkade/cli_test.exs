defmodule Synkade.CLITest do
  use ExUnit.Case, async: true

  alias Synkade.CLI

  describe "parse_args/1" do
    test "parses --port flag" do
      CLI.parse_args(["--port", "5000"])
      config = Application.get_env(:synkade, SynkadeWeb.Endpoint)
      assert config[:http] == [port: 5000]
    after
      Application.delete_env(:synkade, SynkadeWeb.Endpoint)
    end

    test "handles empty args" do
      assert :ok = CLI.parse_args([])
    end

    test "ignores unknown positional args" do
      assert :ok = CLI.parse_args(["something"])
    end
  end
end
