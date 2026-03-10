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
end
