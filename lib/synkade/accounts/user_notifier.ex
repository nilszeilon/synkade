defmodule Synkade.Accounts.UserNotifier do
  import Swoosh.Email

  alias Synkade.Mailer
  alias Synkade.Accounts.User

  # Delivers the email using the application mailer.
  # Returns {:ok, :email_not_configured} when no real mail adapter is set.
  defp deliver(recipient, subject, body) do
    adapter = Application.get_env(:synkade, Synkade.Mailer)[:adapter]

    if adapter in [nil, Swoosh.Adapters.Local] do
      {:ok, :email_not_configured}
    else
      email =
        new()
        |> to(recipient)
        |> from({"Synkade", "noreply@synkade.com"})
        |> subject(subject)
        |> text_body(body)

      with {:ok, _metadata} <- Mailer.deliver(email) do
        {:ok, email}
      end
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end
end
