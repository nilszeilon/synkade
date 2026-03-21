defmodule SynkadeWeb.SetupController do
  use SynkadeWeb, :controller

  alias Synkade.Accounts
  alias Synkade.Accounts.User

  plug :redirect_if_setup_completed

  def new(conn, _params) do
    changeset = User.setup_changeset(%User{}, %{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_setup_user(user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Account created successfully. Please log in.")
        |> redirect(to: ~p"/users/log-in")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  defp redirect_if_setup_completed(conn, _opts) do
    if Accounts.setup_completed?() do
      conn
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    else
      conn
    end
  end
end
