defmodule SynkadeWeb.GitHub.WebhookController do
  use SynkadeWeb, :controller

  require Logger

  alias Synkade.Workflow.Config
  alias Synkade.Settings
  alias Synkade.Settings.ConfigAdapter

  def handle(conn, _params) do
    with {:ok, raw_body} <- get_raw_body(conn),
         {:ok, config} <- get_config(),
         :ok <- verify_signature(conn, raw_body, config) do
      event = get_req_header(conn, "x-github-event") |> List.first()
      handle_event(event, conn.body_params)

      conn
      |> put_status(200)
      |> json(%{ok: true})
    else
      {:error, :no_raw_body} ->
        conn |> put_status(400) |> json(%{error: "missing body"})

      {:error, :no_webhook_secret} ->
        conn |> put_status(500) |> json(%{error: "webhook_secret not configured"})

      {:error, :invalid_signature} ->
        conn |> put_status(401) |> json(%{error: "invalid signature"})

      {:error, :no_config} ->
        conn |> put_status(500) |> json(%{error: "no settings configured"})
    end
  end

  defp get_raw_body(conn) do
    case conn.private[:raw_body] do
      nil -> {:error, :no_raw_body}
      body -> {:ok, body}
    end
  end

  defp get_config do
    case Settings.get_settings() do
      nil -> {:error, :no_config}
      setting -> {:ok, ConfigAdapter.to_config(setting)}
    end
  end

  defp verify_signature(conn, raw_body, config) do
    secret = Config.get(config, "tracker", "webhook_secret")

    if is_nil(secret) or secret == "" do
      {:error, :no_webhook_secret}
    else
      signature = get_req_header(conn, "x-hub-signature-256") |> List.first() || ""

      expected =
        "sha256=" <>
          (:crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode16(case: :lower))

      if Plug.Crypto.secure_compare(signature, expected) do
        :ok
      else
        {:error, :invalid_signature}
      end
    end
  end

  defp handle_event(event, payload) when event in ["installation", "installation_repositories"] do
    action = payload["action"]
    Logger.info("GitHub webhook: #{event}/#{action}")
  end

  defp handle_event(event, _payload) do
    Logger.debug("GitHub webhook: ignoring event #{event}")
    :ok
  end
end
