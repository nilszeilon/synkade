defmodule SynkadeWeb.GitHub.OAuthController do
  use SynkadeWeb, :controller

  require Logger

  alias Synkade.Tracker.GitHub.InstallationRegistry

  def callback(conn, _params) do
    Logger.info("GitHub App installation callback received")
    InstallationRegistry.refresh()

    conn
    |> put_flash(:info, "GitHub App installed successfully. Repos are being discovered.")
    |> redirect(to: ~p"/")
  end
end
