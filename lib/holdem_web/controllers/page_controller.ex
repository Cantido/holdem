defmodule HoldemWeb.PageController do
  use HoldemWeb, :controller

  alias Holdem.Poker.Game

  def home(conn, _params) do
    changeset = Game.changeset(%Game{}, %{players: [%{}]})

    currencies =
      Money.Currency.known_current_currencies()
      |> Enum.map(fn code ->
        {:ok, currency} = Money.Currency.currency_for_code(code)

        {
          Cldr.display_name(currency),
          Atom.to_string(code)
        }
      end)

    render(conn, :home, changeset: changeset, currencies: currencies)
  end
end
