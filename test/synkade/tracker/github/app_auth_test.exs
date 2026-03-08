defmodule Synkade.Tracker.GitHub.AppAuthTest do
  use ExUnit.Case, async: true

  alias Synkade.Tracker.GitHub.AppAuth

  setup do
    pem = Synkade.Test.GitHubAppHelpers.generate_test_private_key()
    %{pem: pem}
  end

  describe "build_jwt/2" do
    test "returns a valid JWT string", %{pem: pem} do
      assert {:ok, jwt} = AppAuth.build_jwt("123456", pem)
      assert is_binary(jwt)

      # Decode and verify claims
      [header_b64, payload_b64, _sig] = String.split(jwt, ".")
      header = header_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()
      payload = payload_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()

      assert header["alg"] == "RS256"
      assert payload["iss"] == "123456"
      assert is_integer(payload["iat"])
      assert is_integer(payload["exp"])
      assert payload["exp"] - payload["iat"] <= 660
    end

    test "returns error for invalid PEM" do
      assert {:error, _} = AppAuth.build_jwt("123456", "not-a-pem")
    end
  end

  describe "fetch_installation_token/3" do
    test "exchanges JWT for installation token", %{pem: pem} do
      plug_name = :app_auth_token
      {:ok, jwt} = AppAuth.build_jwt("123456", pem)

      expires = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_iso8601()

      Req.Test.stub(plug_name, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/app/installations/789/access_tokens"

        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{
          "token" => "ghs_test_token_abc",
          "expires_at" => expires
        })
      end)

      assert {:ok, %{token: "ghs_test_token_abc", expires_at: %DateTime{}}} =
               AppAuth.fetch_installation_token(jwt, 789, req_options: [plug: {Req.Test, plug_name}])
    end

    test "returns error on API failure", %{pem: pem} do
      plug_name = :app_auth_token_fail
      {:ok, jwt} = AppAuth.build_jwt("123456", pem)

      Req.Test.stub(plug_name, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(401, Jason.encode!(%{"message" => "Bad credentials"}))
      end)

      assert {:error, _} =
               AppAuth.fetch_installation_token(jwt, 789, req_options: [plug: {Req.Test, plug_name}])
    end
  end

  describe "list_installations/2" do
    test "returns list of installations", %{pem: pem} do
      plug_name = :app_auth_installations
      {:ok, jwt} = AppAuth.build_jwt("123456", pem)

      Req.Test.stub(plug_name, fn conn ->
        assert conn.request_path == "/app/installations"

        Req.Test.json(conn, [
          %{"id" => 1, "account" => %{"login" => "acme"}},
          %{"id" => 2, "account" => %{"login" => "other-org"}}
        ])
      end)

      assert {:ok, installations} =
               AppAuth.list_installations(jwt, req_options: [plug: {Req.Test, plug_name}])

      assert length(installations) == 2
    end
  end

  describe "list_installation_repos/2" do
    test "returns list of repos", %{pem: _pem} do
      plug_name = :app_auth_repos

      Req.Test.stub(plug_name, fn conn ->
        assert conn.request_path == "/installation/repositories"

        Req.Test.json(conn, %{
          "total_count" => 2,
          "repositories" => [
            %{"full_name" => "acme/api", "private" => false},
            %{"full_name" => "acme/web", "private" => true}
          ]
        })
      end)

      assert {:ok, repos} =
               AppAuth.list_installation_repos("ghs_test", req_options: [plug: {Req.Test, plug_name}])

      assert length(repos) == 2
      assert Enum.any?(repos, &(&1["full_name"] == "acme/api"))
    end
  end
end
