defmodule Synkade.Execution.BackendClientTest do
  use ExUnit.Case, async: true

  alias Synkade.Execution.BackendClient

  describe "backend_for/1" do
    test "defaults to Local backend" do
      assert BackendClient.backend_for(%{}) == Synkade.Execution.Local
    end

    test "selects Local backend explicitly" do
      config = %{"execution" => %{"backend" => "local"}}
      assert BackendClient.backend_for(config) == Synkade.Execution.Local
    end

    test "selects Sprites backend" do
      config = %{"execution" => %{"backend" => "sprites"}}
      assert BackendClient.backend_for(config) == Synkade.Execution.Sprites
    end

    test "raises on unknown backend" do
      config = %{"execution" => %{"backend" => "docker"}}

      assert_raise RuntimeError, ~r/Unsupported execution backend/, fn ->
        BackendClient.backend_for(config)
      end
    end
  end
end
