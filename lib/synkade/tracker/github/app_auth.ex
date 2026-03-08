defmodule Synkade.Tracker.GitHub.AppAuth do
  @moduledoc false

  @github_api "https://api.github.com"

  @doc """
  Builds an RS256 JWT for GitHub App authentication.
  Returns `{:ok, jwt_string}` or `{:error, reason}`.
  """
  @spec build_jwt(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def build_jwt(app_id, private_key_pem) do
    now = System.os_time(:second)

    signer = Joken.Signer.create("RS256", %{"pem" => private_key_pem})

    claims = %{
      "iat" => now - 60,
      "exp" => now + 600,
      "iss" => app_id
    }

    try do
      case Joken.Signer.sign(claims, signer) do
        {:ok, jwt} -> {:ok, jwt}
        {:error, reason} -> {:error, {:jwt_sign_error, reason}}
      end
    rescue
      e -> {:error, {:jwt_sign_error, e}}
    end
  end

  @doc """
  Exchanges a JWT for an installation access token.
  POST /app/installations/:id/access_tokens
  """
  @spec fetch_installation_token(String.t(), String.t() | integer(), keyword()) ::
          {:ok, %{token: String.t(), expires_at: DateTime.t()}} | {:error, term()}
  def fetch_installation_token(jwt, installation_id, opts \\ []) do
    url = "#{@github_api}/app/installations/#{installation_id}/access_tokens"

    req_opts =
      [
        method: :post,
        url: url,
        headers: [
          {"accept", "application/vnd.github+json"},
          {"authorization", "Bearer #{jwt}"}
        ],
        body: "",
        retry: false
      ] ++ Keyword.get(opts, :req_options, [])

    case Req.request(req_opts) do
      {:ok, %{status: 201, body: body}} ->
        {:ok, expires_at, _} = DateTime.from_iso8601(body["expires_at"])
        {:ok, %{token: body["token"], expires_at: expires_at}}

      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all installations for the GitHub App.
  GET /app/installations
  """
  @spec list_installations(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_installations(jwt, opts \\ []) do
    url = "#{@github_api}/app/installations"

    req_opts =
      [
        url: url,
        headers: [
          {"accept", "application/vnd.github+json"},
          {"authorization", "Bearer #{jwt}"}
        ],
        retry: false
      ] ++ Keyword.get(opts, :req_options, [])

    case Req.get(req_opts) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all repositories accessible to an installation token.
  GET /installation/repositories (paginated)
  """
  @spec list_installation_repos(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_installation_repos(token, opts \\ []) do
    url = "#{@github_api}/installation/repositories"
    fetch_repos_page(url, token, opts, [])
  end

  defp fetch_repos_page(url, token, opts, acc) do
    req_opts =
      [
        url: url,
        headers: [
          {"accept", "application/vnd.github+json"},
          {"authorization", "Bearer #{token}"}
        ],
        params: [per_page: 100],
        retry: false
      ] ++ Keyword.get(opts, :req_options, [])

    case Req.get(req_opts) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        repos = body["repositories"] || []
        all = acc ++ repos

        case next_page_url(headers) do
          nil -> {:ok, all}
          next_url -> fetch_repos_page(next_url, token, opts, all)
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp next_page_url(headers) do
    link_header =
      Enum.find(headers, fn {name, _} -> String.downcase(name) == "link" end)

    case link_header do
      {_, value} ->
        value
        |> String.split(",")
        |> Enum.find_value(fn part ->
          if String.contains?(part, "rel=\"next\"") do
            case Regex.run(~r/<([^>]+)>/, part) do
              [_, url] -> url
              _ -> nil
            end
          end
        end)

      nil ->
        nil
    end
  end
end
