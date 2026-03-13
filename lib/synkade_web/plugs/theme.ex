defmodule SynkadeWeb.Plugs.Theme do
  @moduledoc "Reads the theme from settings and assigns it to the conn."
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    theme =
      case Synkade.Settings.get_settings() do
        %{theme: theme} when is_binary(theme) -> theme
        _ -> "ops"
      end

    assign(conn, :theme, theme)
  end
end
