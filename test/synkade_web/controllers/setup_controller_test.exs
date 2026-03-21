defmodule SynkadeWeb.SetupControllerTest do
  use SynkadeWeb.ConnCase

  import Synkade.AccountsFixtures

  describe "GET /setup" do
    test "renders setup page when no users exist", %{conn: conn} do
      conn = get(conn, ~p"/setup")
      response = html_response(conn, 200)
      assert response =~ "Welcome to Synkade"
      assert response =~ "Create your admin account"
    end

    test "redirects to login when setup is already completed", %{conn: conn} do
      user_fixture()
      conn = get(conn, ~p"/setup")
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /setup" do
    test "creates admin account and redirects to login", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/setup", %{
          "user" => %{
            "email" => email,
            "password" => valid_user_password(),
            "password_confirmation" => valid_user_password()
          }
        })

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Account created successfully"

      # Verify user was created and confirmed
      user = Synkade.Accounts.get_user_by_email(email)
      assert user
      assert user.confirmed_at
    end

    test "renders errors for invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/setup", %{
          "user" => %{"email" => "bad", "password" => "short"}
        })

      response = html_response(conn, 200)
      assert response =~ "Welcome to Synkade"
      assert response =~ "must have the @ sign and no spaces"
    end

    test "renders errors for password mismatch", %{conn: conn} do
      conn =
        post(conn, ~p"/setup", %{
          "user" => %{
            "email" => unique_user_email(),
            "password" => valid_user_password(),
            "password_confirmation" => "different password"
          }
        })

      response = html_response(conn, 200)
      assert response =~ "does not match password"
    end

    test "prevents second account creation after setup", %{conn: conn} do
      user_fixture()

      conn =
        post(conn, ~p"/setup", %{
          "user" => %{
            "email" => unique_user_email(),
            "password" => valid_user_password(),
            "password_confirmation" => valid_user_password()
          }
        })

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end
