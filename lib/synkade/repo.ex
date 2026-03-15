defmodule Synkade.Repo do
  use Ecto.Repo,
    otp_app: :synkade,
    adapter: Ecto.Adapters.SQLite3
end
