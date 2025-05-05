defmodule Holdem.Repo.Migrations.AddGames do
  use Ecto.Migration

  def change do
    create table(:players) do
      add :name, :string, null: false

      timestamps()
    end

    create table(:games) do
      add :community_cards, {:array, :map}
      add :deck, {:array, :map}
      add :round, :integer, null: false
      add :big_blind, :decimal, null: false

      timestamps()
    end

    create constraint(:games, :round_within_range, check: "round >= 0 AND round <= 4")

    create table(:game_players, primary_key: false) do
      add :game_id, references(:games, on_update: :update_all, on_delete: :delete_all),
        primary_key: true

      add :player_id, references(:players, on_update: :update_all, on_delete: :delete_all),
        primary_key: true

      add :position, :integer, null: false

      add :cards, {:array, :map}

      add :bet, :decimal, default: 0

      add :is_dealer, :boolean, default: false
      add :is_winner, :boolean, default: false
      add :is_under_the_gun, :boolean, default: false
      add :is_folded, :boolean, default: false
    end

    create constraint(:game_players, :folded_cannot_win,
             check:
               "(is_winner AND NOT is_folded) OR (NOT is_winner and is_folded) OR (NOT is_winner AND NOT is_folded)"
           )

    create unique_index(:game_players, [:game_id, :player_id, :position])

    create unique_index(:game_players, [:game_id, :player_id],
             name: "game_players_game_id_player_id_where_is_under_the_gun_idx",
             where: "is_under_the_gun"
           )

    create unique_index(:game_players, [:game_id, :player_id],
             name: "game_players_game_id_player_id_where_is_dealer_idx",
             where: "is_dealer"
           )
  end
end
