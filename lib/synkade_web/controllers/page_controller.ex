defmodule SynkadeWeb.PageController do
  use SynkadeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
