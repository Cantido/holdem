defmodule Holdem.Poker.Game do
  use Ecto.Schema

  alias Holdem.Card
  alias Holdem.Poker.Player

  import Ecto.Changeset

  schema "games" do
    has_many :players, Player, preload_order: [asc: :position]

    field :slug, :string, autogenerate: {Nanoid, :generate, [8]}
    field :state, Ecto.Enum, values: [:waiting_for_players, :playing, :finished]
    field :round, :integer, default: 0
    field :bet, Money.Ecto.Composite.Type
    field :player_starting_bankroll, Money.Ecto.Composite.Type

    embeds_many :community_cards, Card, on_replace: :delete
    embeds_many :deck, Card, on_replace: :delete

    timestamps()
  end

  def changeset(model, params) do
    model
    |> cast(params, [:bet, :player_starting_bankroll])
    |> cast_assoc(:players)
    |> validate_required([:bet])
  end
end
