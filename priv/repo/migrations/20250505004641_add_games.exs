defmodule Holdem.Repo.Migrations.AddGames do
  use Ecto.Migration

  def change do
    create table(:games) do
      add :community_cards, {:array, :map}
      add :deck, {:array, :map}
      add :round, :integer, null: false
      add :big_blind, :decimal, null: false
      add :state, :string, default: "waiting_for_players"

      timestamps()
    end

    create constraint(:games, :round_within_range, check: "round >= 0 AND round <= 4")

    create table(:players) do
      add :game_id, references(:games, on_update: :update_all, on_delete: :delete_all)

      add :name, :string, null: false

      add :position, :integer, null: false

      add :cards, {:array, :map}

      add :bet, :decimal, default: 0

      add :is_dealer, :boolean, default: false
      add :is_winner, :boolean, default: false
      add :is_under_the_gun, :boolean, default: false
      add :is_folded, :boolean, default: false
    end

    create constraint(:players, :folded_cannot_win,
             check:
               "(is_winner AND NOT is_folded) OR (NOT is_winner and is_folded) OR (NOT is_winner AND NOT is_folded)"
           )

    create unique_index(:players, [:id, :game_id, :position])

    create unique_index(:players, [:id, :game_id],
             name: "players_id_game_id_where_is_under_the_gun_idx",
             where: "is_under_the_gun"
           )

    create unique_index(:players, [:id, :game_id],
             name: "players_id_game_id_where_is_dealer_idx",
             where: "is_dealer"
           )
  end
end
