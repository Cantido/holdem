defmodule Holdem.Poker.GamePlayer do
  use Ecto.Schema

  alias Holdem.Card
  alias Holdem.Poker.Game
  alias Holdem.Poker.Player

  @primary_key false

  schema "game_players" do
    belongs_to :game, Game, primary_key: true
    belongs_to :player, Player, primary_key: true
    embeds_many :cards, Card, on_replace: :delete

    field :position, :integer
    field :bet, :decimal
    field :is_dealer, :boolean
    field :is_winner, :boolean
    field :is_under_the_gun, :boolean
    field :is_folded, :boolean
  end
end
