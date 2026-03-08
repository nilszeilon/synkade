defmodule Synkade.Tracker.GitHub.TokenServerTest do
  use ExUnit.Case, async: true

  alias Synkade.Tracker.GitHub.TokenServer

  setup do
    pem = Synkade.Test.GitHubAppHelpers.generate_test_private_key()
    %{pem: pem}
  end

  test "fetches and caches token", %{pem: pem} do
    plug_name = :"ts_fetch_#{System.unique_integer([:positive])}"
    installation_id = "inst_#{System.unique_integer([:positive])}"

    expires = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_iso8601()

    Req.Test.stub(plug_name, fn conn ->
      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{
        "token" => "ghs_cached_token",
        "expires_at" => expires
      })
    end)

    pid =
      start_supervised!(
        {TokenServer,
         installation_id: installation_id,
         app_id: "123",
         private_key_pem: pem,
         req_options: [plug: {Req.Test, plug_name}]},
        id: {:token_server, installation_id}
      )

    # Allow the GenServer process to access the stub
    Req.Test.allow(plug_name, self(), pid)

    assert {:ok, "ghs_cached_token"} = GenServer.call(pid, :get_token)

    # Second call should use cache
    assert {:ok, "ghs_cached_token"} = GenServer.call(pid, :get_token)
  end
end
