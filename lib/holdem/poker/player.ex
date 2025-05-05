defmodule Holdem.Poker.Player do
  use Ecto.Schema

  alias Holdem.Poker.Game
  alias Holdem.Poker.GamePlayer

  import Ecto.Changeset

  schema "players" do
    field :name, :string

    many_to_many :games, Game, join_through: GamePlayer

    timestamps()
  end

  def changeset(model, params) do
    model
    |> cast(params, [:name])
    |> validate_required([:name])
  end
end
