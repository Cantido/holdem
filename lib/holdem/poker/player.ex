defmodule Holdem.Poker.Player do
  use Ecto.Schema

  alias Holdem.Card
  alias Holdem.Poker.Game

  import Ecto.Changeset

  schema "players" do
    belongs_to :game, Game
    embeds_many :cards, Card, on_replace: :delete

    field :name, :string
    field :position, :integer
    field :last_action, Ecto.Enum, values: [:call, :check, :fold, :open, :raise]
    field :is_dealer, :boolean
    field :is_winner, :boolean
    field :is_active, :boolean
    field :is_folded, :boolean
    field :bankroll, Money.Ecto.Composite.Type
    field :bet, Money.Ecto.Composite.Type
    field :bet_this_round, Money.Ecto.Composite.Type

    timestamps()
  end

  def changeset(model, params) do
    model
    |> cast(params, [:name])
    |> assoc_constraint(:game)
    |> validate_required([:name])
    |> prepare_changes(fn changeset ->
      if get_field(changeset, :position) do
        changeset
      else
        game_id = get_field(changeset, :game_id)

        player_count =
          changeset.repo.get!(Game, game_id)
          |> changeset.repo.preload(:players)
          |> Map.get(:players)
          |> Enum.count()

        put_change(changeset, :position, player_count)
      end
    end)
    |> prepare_changes(fn changeset ->
      position = get_field(changeset, :position)

      if position == 0 do
        put_change(changeset, :is_dealer, true)
      else
        changeset
      end
    end)
    |> prepare_changes(fn changeset ->
      if get_field(changeset, :bet) do
        changeset
      else
        game_id = get_field(changeset, :game_id)
        game = changeset.repo.get!(Game, game_id)

        put_change(changeset, :bet, Money.zero(game.bet))
      end
    end)
    |> prepare_changes(fn changeset ->
      if get_field(changeset, :bet_this_round) do
        changeset
      else
        game_id = get_field(changeset, :game_id)
        game = changeset.repo.get!(Game, game_id)

        put_change(changeset, :bet_this_round, Money.zero(game.bet))
      end
    end)
    |> prepare_changes(fn changeset ->
      if get_field(changeset, :bankroll) do
        changeset
      else
        game_id = get_field(changeset, :game_id)
        game = changeset.repo.get!(Game, game_id)

        put_change(changeset, :bankroll, game.player_starting_bankroll)
      end
    end)
  end
end
