defmodule SynkadeWeb.Plugs.CacheBodyReader do
  @moduledoc false

  @doc """
  A custom body reader that caches the raw body for webhook signature verification.
  Used as the `:body_reader` option in `Plug.Parsers`.
  """
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = Plug.Conn.put_private(conn, :raw_body, body)
        {:ok, body, conn}

      {:more, body, conn} ->
        conn = Plug.Conn.put_private(conn, :raw_body, body)
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
