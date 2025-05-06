defmodule HoldemWeb.GameController do
  use HoldemWeb, :controller

  alias Holdem.Poker.Game
  alias Holdem.Card
  alias Holdem.Repo
  alias Holdem.Poker.Player
  alias Phoenix.PubSub

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"big-blind" => big_blind, "player-name" => name}) do
    {:ok, {game, player}} =
      Repo.transaction(fn ->
        big_blind = Decimal.new(big_blind)

        game =
          %Game{}
          |> Ecto.Changeset.change(%{
            big_blind: big_blind,
            community_cards: [],
            deck: Card.deck() |> Enum.shuffle()
          })
          |> Repo.insert!()

        player =
          %Player{
            name: name,
            game_id: game.id,
            position: 0,
            is_dealer: true
          }
          |> Ecto.Changeset.change(%{})
          |> Repo.insert!()

        {game, player}
      end)

    conn
    |> put_session(:player_id, player.id)
    |> redirect(to: "/game/#{game.id}")
  end

  def new_player(conn, %{"id" => game_id}) do
    game = Repo.get!(Game, game_id)
    render(conn, game_id: game.id)
  end

  def join(conn, %{"id" => game_id, "player-name" => name}) do
    game = Repo.get!(Game, game_id) |> Repo.preload(:players)

    last_position =
      Enum.map(game.players, & &1.position)
      |> Enum.max()

    player =
      %Player{
        name: name,
        game_id: game.id,
        position: last_position + 1
      }
      |> Ecto.Changeset.change(%{})
      |> Repo.insert!()

    PubSub.broadcast(Holdem.PubSub, "game:#{game.id}", {:player_joined, player.id})

    conn
    |> put_session(:player_id, player.id)
    |> redirect(to: "/game/#{game_id}")
  end
end
