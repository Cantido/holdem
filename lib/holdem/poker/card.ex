defmodule Holdem.Card do
  use Ecto.Schema

  embedded_schema do
    field :suit, Ecto.Enum, values: [:clubs, :diamonds, :hearts, :spades]
    field :rank, :integer
  end

  def deck do
    for suit <- ~w(clubs diamonds hearts spades)a, rank <- 2..14 do
      %__MODULE__{suit: suit, rank: rank}
    end
  end
end
