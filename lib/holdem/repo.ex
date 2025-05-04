defmodule Holdem.Repo do
  use Ecto.Repo,
    otp_app: :holdem,
    adapter: Ecto.Adapters.Postgres
end
