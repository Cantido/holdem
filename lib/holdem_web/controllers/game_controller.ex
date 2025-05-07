defmodule HoldemWeb.GameController do
  use HoldemWeb, :controller

  alias Holdem.Poker
  alias Holdem.Poker.Game
  alias Holdem.Repo
  alias Holdem.Poker.Player
  alias Phoenix.PubSub

  def create(conn, %{"game" => game_params, "currency" => currency}) do
    bet = Money.new(game_params["bet"], currency)

    {:ok, game} =
      game_params
      |> Map.put("bet", bet)
      |> Poker.create_game()

    game = Repo.preload(game, :players)

    player = List.first(game.players)

    conn
    |> put_session(:player_id, player.id)
    |> redirect(to: "/game/#{game.slug}")
  end

  def new_player(conn, %{"slug" => game_slug}) do
    game = Repo.get_by!(Game, slug: game_slug)

    changeset = Player.changeset(%Player{}, %{})

    render(conn, game_slug: game.slug, changeset: changeset)
  end

  def join(conn, %{"slug" => game_slug, "player" => params}) do
    game = Repo.get_by!(Game, slug: game_slug)
    {:ok, player} = Poker.create_player(game.id, params)

    PubSub.broadcast(Holdem.PubSub, "game:#{game.id}", {:player_joined, player.id})

    conn
    |> put_session(:player_id, player.id)
    |> redirect(to: "/game/#{game.slug}")
  end
end
