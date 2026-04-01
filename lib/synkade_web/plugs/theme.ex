defmodule SynkadeWeb.Plugs.Theme do
  @moduledoc "Reads the theme from settings and assigns it to the conn."
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    theme =
      case conn.assigns[:current_scope] do
        %{user: user} when not is_nil(user) ->
          case Synkade.Settings.get_settings_for_user(user.id) do
            %{theme: theme} when is_binary(theme) -> theme
            _ -> "paper"
          end

        _ ->
          "paper"
      end

    assign(conn, :theme, theme)
  end
end
