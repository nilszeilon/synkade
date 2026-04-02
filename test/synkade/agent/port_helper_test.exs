defmodule Synkade.Agent.PortHelperTest do
  use ExUnit.Case, async: true

  alias Synkade.Agent.PortHelper

  describe "shell_escape/1" do
    test "wraps argument in single quotes" do
      assert PortHelper.shell_escape("hello") == "'hello'"
    end

    test "escapes single quotes within argument" do
      assert PortHelper.shell_escape("it's") == "'it'\\''s'"
    end

    test "handles empty string" do
      assert PortHelper.shell_escape("") == "''"
    end

    test "handles argument with spaces" do
      assert PortHelper.shell_escape("hello world") == "'hello world'"
    end

    test "handles argument with multiple single quotes" do
      assert PortHelper.shell_escape("a'b'c") == "'a'\\''b'\\''c'"
    end
  end

  describe "port_os_pid/1" do
    test "returns nil for invalid port" do
      # Port.info on a closed/invalid reference returns nil
      port = Port.open({:spawn, "echo hi"}, [:binary])
      Port.close(port)
      assert PortHelper.port_os_pid(port) == nil
    end
  end

  describe "resolve_github_token/1" do
    test "returns tracker api_key when present" do
      config = %{"tracker" => %{"api_key" => "ghp_tracker_token"}}
      assert PortHelper.resolve_github_token(config) == "ghp_tracker_token"
    end

    test "falls back to GITHUB_TOKEN env var when tracker api_key is nil" do
      config = %{"tracker" => %{}}
      System.put_env("GITHUB_TOKEN", "ghp_env_token")

      assert PortHelper.resolve_github_token(config) == "ghp_env_token"

      System.delete_env("GITHUB_TOKEN")
    end

    test "falls back to GITHUB_TOKEN env var when tracker api_key is empty" do
      config = %{"tracker" => %{"api_key" => ""}}
      System.put_env("GITHUB_TOKEN", "ghp_env_token")

      assert PortHelper.resolve_github_token(config) == "ghp_env_token"

      System.delete_env("GITHUB_TOKEN")
    end

    test "returns nil when neither tracker api_key nor env var set" do
      config = %{"tracker" => %{}}
      System.delete_env("GITHUB_TOKEN")

      assert PortHelper.resolve_github_token(config) == nil
    end

    test "returns nil when no tracker config at all" do
      config = %{}
      System.delete_env("GITHUB_TOKEN")

      assert PortHelper.resolve_github_token(config) == nil
    end
  end

  describe "common_env/2" do
    test "appends GITHUB_TOKEN from tracker config" do
      config = %{"tracker" => %{"api_key" => "ghp_test"}}
      env = PortHelper.common_env(config, [])

      assert {~c"GITHUB_TOKEN", ~c"ghp_test"} in env
    end

    test "appends SYNKADE_API_URL and SYNKADE_API_TOKEN" do
      config = %{
        "agent" => %{
          "synkade_api_url" => "http://localhost:4000",
          "synkade_api_token" => "tok_abc"
        }
      }

      env = PortHelper.common_env(config, [])

      assert {~c"SYNKADE_API_URL", ~c"http://localhost:4000"} in env
      assert {~c"SYNKADE_API_TOKEN", ~c"tok_abc"} in env
    end

    test "preserves initial agent_env entries" do
      config = %{}
      initial = [{~c"MY_KEY", ~c"my_value"}]
      env = PortHelper.common_env(config, initial)

      assert {~c"MY_KEY", ~c"my_value"} in env
    end

    test "skips nil and empty string values" do
      config = %{
        "agent" => %{
          "synkade_api_url" => nil,
          "synkade_api_token" => ""
        }
      }

      System.delete_env("GITHUB_TOKEN")
      env = PortHelper.common_env(config, [])

      assert env == []
    end
  end
end
