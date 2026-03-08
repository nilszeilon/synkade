defmodule Synkade.Settings.ConnectionTestTest do
  use ExUnit.Case, async: true

  alias Synkade.Settings.ConnectionTest, as: ConnTest

  setup do
    Req.Test.stub(:github_conn_test, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/user"} ->
          auth = Plug.Conn.get_req_header(conn, "authorization")

          if auth == ["Bearer valid_token"] do
            Req.Test.json(conn, %{"login" => "testuser"})
          else
            conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"message" => "Bad credentials"})
          end

        {"GET", "/app"} ->
          Req.Test.json(conn, %{"name" => "My GitHub App"})

        _ ->
          conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not found"})
      end
    end)

    :ok
  end

  @req_opts [plug: {Req.Test, :github_conn_test}]

  describe "test_pat/3" do
    test "returns ok for valid token" do
      assert {:ok, "Connected as @testuser"} =
               ConnTest.test_pat("valid_token", nil, @req_opts)
    end

    test "returns error for invalid token" do
      assert {:error, "Authentication failed: invalid token"} =
               ConnTest.test_pat("bad_token", nil, @req_opts)
    end
  end

  describe "test_app/4" do
    test "returns ok for valid app credentials" do
      # Generate a real RSA key for testing
      key = :public_key.generate_key({:rsa, 2048, 65537})
      pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, key)])

      assert {:ok, "Connected as My GitHub App"} =
               ConnTest.test_app("123456", pem, nil, @req_opts)
    end

    test "returns error for invalid PEM" do
      assert {:error, "Invalid private key:" <> _} =
               ConnTest.test_app("123456", "not-a-pem", nil)
    end
  end
end
