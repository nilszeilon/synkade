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
end
