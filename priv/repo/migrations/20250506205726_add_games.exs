defmodule Holdem.Repo.Migrations.AddGames do
  use Ecto.Migration

  def change do
    create table(:games) do
      add :slug, :string, null: false
      add :community_cards, {:array, :map}
      add :deck, {:array, :map}
      add :round, :integer, null: false
      add :state, :string, default: "waiting_for_players"
      add :player_starting_bankroll, :money_with_currency
      add :bet, :money_with_currency, null: false

      timestamps()
    end

    create constraint(:games, :round_within_range, check: "round >= 0 AND round <= 4")
    create unique_index(:games, [:slug])

    create table(:players) do
      add :game_id, references(:games, on_update: :update_all, on_delete: :delete_all),
        null: false

      add :name, :string, null: false

      add :position, :integer, null: false

      add :cards, {:array, :map}

      add :bankroll, :money_with_currency, null: false
      add :bet, :money_with_currency, null: false
      add :bet_this_round, :money_with_currency

      add :last_action, :string

      add :is_dealer, :boolean, default: false
      add :is_winner, :boolean, default: false
      add :is_active, :boolean, default: false
      add :is_folded, :boolean, default: false

      timestamps()
    end

    create constraint(:players, :folded_cannot_win,
             check:
               "(is_winner AND NOT is_folded) OR (NOT is_winner and is_folded) OR (NOT is_winner AND NOT is_folded)"
           )

    create unique_index(:players, [:id, :game_id, :position])

    create unique_index(:players, [:id, :game_id],
             name: "players_id_game_id_where_is_active_idx",
             where: "is_active"
           )

    create unique_index(:players, [:id, :game_id],
             name: "players_id_game_id_where_is_dealer_idx",
             where: "is_dealer"
           )
  end
end
