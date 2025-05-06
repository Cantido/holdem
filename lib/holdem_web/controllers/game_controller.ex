defmodule HoldemWeb.GameController do
  use HoldemWeb, :controller

  alias Holdem.Poker
  alias Holdem.Poker.Game
  alias Holdem.Repo
  alias Holdem.Poker.Player
  alias Phoenix.PubSub

  def create(conn, %{"game" => params}) do
    {:ok, game} =
      Poker.create_game(params)

    game = Repo.preload(game, :players)

    player = List.first(game.players)

    conn
    |> put_session(:player_id, player.id)
    |> redirect(to: "/game/#{game.id}")
  end

  def new_player(conn, %{"id" => game_id}) do
    game = Repo.get!(Game, game_id)

    changeset = Player.changeset(%Player{}, %{})

    render(conn, game_id: game.id, changeset: changeset)
  end

  def join(conn, %{"id" => game_id, "player" => params}) do
    {:ok, player} = Poker.create_player(game_id, params)

    PubSub.broadcast(Holdem.PubSub, "game:#{game_id}", {:player_joined, player.id})

    conn
    |> put_session(:player_id, player.id)
    |> redirect(to: "/game/#{game_id}")
  end
end
