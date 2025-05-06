defmodule Holdem.Poker.Game do
  use Ecto.Schema

  alias Holdem.Card
  alias Holdem.Poker.Player

  import Ecto.Changeset

  schema "games" do
    has_many :players, Player, preload_order: [asc: :position]

    field :state, Ecto.Enum, values: [:waiting_for_players, :playing, :finished]
    field :round, :integer, default: 0
    field :big_blind, :decimal

    embeds_many :community_cards, Card, on_replace: :delete
    embeds_many :deck, Card, on_replace: :delete

    timestamps()
  end

  def changeset(model, params) do
    model
    |> cast(params, [:big_blind])
    |> cast_assoc(:players)
    |> validate_required([:big_blind])
  end
end
