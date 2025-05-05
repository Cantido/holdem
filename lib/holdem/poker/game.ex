defmodule Holdem.Poker.Game do
  use Ecto.Schema

  alias Holdem.Card
  alias Holdem.Poker.Player

  schema "games" do
    has_many :players, Player, preload_order: [asc: :position]

    field :round, :integer, default: 0
    field :big_blind, :decimal

    embeds_many :community_cards, Card, on_replace: :delete
    embeds_many :deck, Card, on_replace: :delete

    timestamps()
  end
end
