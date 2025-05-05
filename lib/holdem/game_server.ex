defmodule Holdem.GameServer do
  alias Holdem.Poker.Player
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    big_blind_bet = Keyword.fetch!(opts, :big_blind_bet)

    {:ok,
     %{
       players: [],
       button_player: 0,
       deck: nil,
       round: 0,
       big_blind_bet: big_blind_bet,
       player_under_the_gun: nil,
       community_cards: [],
       winner: nil
     }}
  end

  def add_player(pid) do
    GenServer.call(pid, :add_player)
  end

  def handle_call(:add_player, _from, state) do
    state =
      state
      |> Map.update!(:players, fn players -> players ++ [%Player{}] end)

    {:reply, {:ok, Enum.count(state.players) - 1}, state}
  end
end
