defmodule Holdem.Poker.Game do
  use Ecto.Schema

  alias Holdem.Card
  alias Holdem.Poker.GamePlayer
  alias Holdem.Poker.Player

  schema "games" do
    has_many :game_players, GamePlayer, preload_order: [asc: :position]
    many_to_many :players, Player, join_through: GamePlayer

    field :round, :integer, default: 0
    field :big_blind, :decimal

    embeds_many :community_cards, Card, on_replace: :delete
    embeds_many :deck, Card, on_replace: :delete

    timestamps()
  end
end
