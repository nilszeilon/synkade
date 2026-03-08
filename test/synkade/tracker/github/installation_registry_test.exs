defmodule Synkade.Tracker.GitHub.InstallationRegistryTest do
  use ExUnit.Case, async: true

  alias Synkade.Tracker.GitHub.InstallationRegistry

  setup do
    pem = Synkade.Test.GitHubAppHelpers.generate_test_private_key()
    %{pem: pem}
  end

  test "discovers repos from installations", %{pem: pem} do
    plug_name = :"ir_discover_#{System.unique_integer([:positive])}"
    pubsub_name = :"ir_pubsub_#{System.unique_integer([:positive])}"

    start_supervised!({Phoenix.PubSub, name: pubsub_name})
    Phoenix.PubSub.subscribe(pubsub_name, InstallationRegistry.pubsub_topic())

    expires = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_iso8601()

    Req.Test.stub(plug_name, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/app/installations"} ->
          Req.Test.json(conn, [%{"id" => 101, "account" => %{"login" => "acme"}}])

        {"POST", "/app/installations/101/access_tokens"} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"token" => "ghs_ir_token", "expires_at" => expires})

        {"GET", "/installation/repositories"} ->
          Req.Test.json(conn, %{
            "total_count" => 2,
            "repositories" => [
              %{"full_name" => "acme/api"},
              %{"full_name" => "acme/web"}
            ]
          })
      end
    end)

    name = :"ir_test_#{System.unique_integer([:positive])}"

    pid =
      start_supervised!(
        {InstallationRegistry,
         name: name,
         app_id: "123",
         private_key_pem: pem,
         pubsub: pubsub_name,
         req_options: [plug: {Req.Test, plug_name}]}
      )

    Req.Test.allow(plug_name, self(), pid)

    # Wait for discovery
    assert_receive {:repos_changed, repos}, 5000

    assert length(repos) == 2
    assert Enum.any?(repos, &(&1.repo == "acme/api"))
    assert Enum.any?(repos, &(&1.repo == "acme/web"))
    assert Enum.all?(repos, &(&1.installation_id == 101))

    # list_repos should return the same
    assert InstallationRegistry.list_repos(name) == repos
  end

  test "handles discovery failure gracefully", %{pem: pem} do
    plug_name = :"ir_fail_#{System.unique_integer([:positive])}"
    pubsub_name = :"ir_pubsub_fail_#{System.unique_integer([:positive])}"

    start_supervised!({Phoenix.PubSub, name: pubsub_name})

    Req.Test.stub(plug_name, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(500, Jason.encode!(%{"message" => "Internal Server Error"}))
    end)

    name = :"ir_fail_test_#{System.unique_integer([:positive])}"

    pid =
      start_supervised!(
        {InstallationRegistry,
         name: name,
         app_id: "123",
         private_key_pem: pem,
         pubsub: pubsub_name,
         req_options: [plug: {Req.Test, plug_name}]}
      )

    Req.Test.allow(plug_name, self(), pid)

    # Give it time to attempt discovery (and fail gracefully)
    Process.sleep(200)

    # Should return empty list, not crash
    assert InstallationRegistry.list_repos(name) == []
  end
end
