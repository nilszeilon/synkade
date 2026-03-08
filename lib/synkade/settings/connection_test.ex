defmodule Synkade.Settings.ConnectionTest do
  @moduledoc false

  @doc "Test a PAT token by calling GET /user."
  def test_pat(token, endpoint, opts \\ []) do
    endpoint = if endpoint in [nil, ""], do: "https://api.github.com", else: endpoint
    url = "#{endpoint}/user"

    req_opts =
      [
        url: url,
        headers: [
          {"authorization", "Bearer #{token}"},
          {"accept", "application/vnd.github+json"}
        ],
        retry: false
      ] ++ opts

    case Req.get(req_opts) do
      {:ok, %{status: 200, body: %{"login" => login}}} ->
        {:ok, "Connected as @#{login}"}

      {:ok, %{status: 401}} ->
        {:error, "Authentication failed: invalid token"}

      {:ok, %{status: status}} ->
        {:error, "Unexpected status #{status}"}

      {:error, reason} ->
        {:error, "Connection failed: #{inspect(reason)}"}
    end
  end

  @doc "Test a GitHub App by building a JWT and calling GET /app."
  def test_app(app_id, pem, endpoint, opts \\ []) do
    endpoint = if endpoint in [nil, ""], do: "https://api.github.com", else: endpoint

    with {:ok, jwt} <- build_jwt(app_id, pem) do
      url = "#{endpoint}/app"

      req_opts =
        [
          url: url,
          headers: [
            {"authorization", "Bearer #{jwt}"},
            {"accept", "application/vnd.github+json"}
          ],
          retry: false
        ] ++ opts

      case Req.get(req_opts) do
        {:ok, %{status: 200, body: %{"name" => name}}} ->
          {:ok, "Connected as #{name}"}

        {:ok, %{status: 401}} ->
          {:error, "Authentication failed: invalid App ID or private key"}

        {:ok, %{status: status}} ->
          {:error, "Unexpected status #{status}"}

        {:error, reason} ->
          {:error, "Connection failed: #{inspect(reason)}"}
      end
    end
  end

  defp build_jwt(app_id, pem) do
    try do
      now = DateTime.utc_now() |> DateTime.to_unix()

      signer = Joken.Signer.create("RS256", %{"pem" => pem})

      claims = %{
        "iat" => now - 60,
        "exp" => now + 600,
        "iss" => app_id
      }

      case Joken.Signer.sign(claims, signer) do
        {:ok, jwt} -> {:ok, jwt}
        {:error, reason} -> {:error, "Failed to sign JWT: #{inspect(reason)}"}
      end
    rescue
      e -> {:error, "Invalid private key: #{Exception.message(e)}"}
    end
  end
end
