defmodule SynkadeWeb.UserSessionHTML do
  use SynkadeWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:synkade, Synkade.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
