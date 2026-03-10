defmodule SynkadeWeb.GitHub.WebhookControllerTest do
  use SynkadeWeb.ConnCase, async: false

  alias Synkade.Settings

  @webhook_secret "test_webhook_secret_123"

  setup do
    {:ok, _setting} =
      Settings.save_settings(%{
        "github_pat" => "ghp_test123",
        "github_webhook_secret" => @webhook_secret
      })

    :ok
  end

  test "returns 200 for valid signature", %{conn: conn} do
    payload = Jason.encode!(%{"action" => "created", "installation" => %{"id" => 1}})
    signature = compute_signature(payload)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-github-event", "installation")
      |> put_req_header("x-hub-signature-256", signature)
      |> put_private_raw_body(payload)
      |> post("/github/webhooks", payload)

    assert json_response(conn, 200)["ok"] == true
  end

  test "returns 401 for invalid signature", %{conn: conn} do
    payload = Jason.encode!(%{"action" => "created"})

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-github-event", "installation")
      |> put_req_header("x-hub-signature-256", "sha256=invalid")
      |> put_private_raw_body(payload)
      |> post("/github/webhooks", payload)

    assert json_response(conn, 401)["error"] == "invalid signature"
  end

  test "returns 400 when raw body is missing", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-github-event", "installation")
      |> post("/github/webhooks", %{})

    assert json_response(conn, 400)["error"] == "missing body"
  end

  defp compute_signature(payload) do
    mac = :crypto.mac(:hmac, :sha256, @webhook_secret, payload)
    "sha256=" <> Base.encode16(mac, case: :lower)
  end

  defp put_private_raw_body(conn, body) do
    Plug.Conn.put_private(conn, :raw_body, body)
  end
end
