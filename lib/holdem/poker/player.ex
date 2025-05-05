defmodule Holdem.Poker.Player do
  use Ecto.Schema

  alias Holdem.Card
  alias Holdem.Poker.Game

  schema "players" do
    belongs_to :game, Game
    embeds_many :cards, Card, on_replace: :delete

    field :name, :string
    field :position, :integer
    field :bet, :decimal
    field :is_dealer, :boolean
    field :is_winner, :boolean
    field :is_under_the_gun, :boolean
    field :is_folded, :boolean
  end
end
