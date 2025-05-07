defmodule HoldemWeb.GameLive do
  alias Holdem.Poker.Scope
  alias Holdem.Poker
  use HoldemWeb, :live_view

  alias Holdem.Card
  alias Holdem.Poker.Game
  alias Holdem.Poker.Player
  alias Phoenix.PubSub
  alias Holdem.Repo

  @suits ~w(hearts diamonds spades clubs)a

  def render(assigns) do
    ~H"""
    <.info_bar game={@game} player={@player} />
    <.opponents_pane game={@game} player={@player} />
    <.table_pane game={@game} />
    <.player_pane game={@game} player={@player} action_form={@action_form} />
    """
  end

  defp decimal_sum(enum) do
    {:ok, sum} = Money.sum(enum)

    sum
  end

  attr :game, Game, required: true
  attr :player, Player, required: true

  defp info_bar(assigns) do
    ~H"""
    <div
      :if={@game.state == :waiting_for_players && !@player.is_dealer}
      class="bg-accent text-accent-content text-3xl text-center p-4"
    >
      Waiting for dealer to start the game
    </div>
    <div
      :if={@game.state == :waiting_for_players && @player.is_dealer}
      class="bg-accent text-accent-content text-3xl text-center p-4"
    >
      Waiting for you to start the game <button class="btn" phx-click="start-game">Start</button>
    </div>
    <% winner = Enum.find(@game.players, & &1.is_winner) %>
    <div :if={winner} class="bg-accent text-accent-conent text-3xl text-center p-4">
      {winner.name} wins!
    </div>
    """
  end

  attr :game, Game, required: true

  defp table_pane(assigns) do
    ~H"""
    <div class="bg-base-300 p-8">
      <div class="flex flex-row gap-2 justify-center mb-8">
        <.card
          :for={%Card{suit: suit, rank: value} <- @game.community_cards}
          width="100"
          suit={suit}
          value={value}
        />
        <div
          :for={_i <- Stream.cycle([nil]) |> Stream.take(5 - Enum.count(@game.community_cards))}
          class="w-[100px] h-36 border border-dashed rounded"
        >
        </div>
      </div>
      <div class="text-center text-4xl">
        {Money.to_string!(decimal_sum(Enum.map(@game.players, fn p -> p.bet end)))}
      </div>
    </div>
    """
  end

  attr :game, Game, required: true
  attr :player, Player, required: true

  defp opponents_pane(assigns) do
    ~H"""
    <% {later, sooner} =
      @game.players
      |> Enum.split(@player.position + 1)

    players_around_table =
      (sooner ++ later)
      |> Enum.reject(&(&1.id == @player.id)) %>

    <div class="flex flex-row justify-center">
      <div
        :for={player <- players_around_table}
        class={[
          "w-48 p-2",
          player.is_folded && "bg-base-200",
          !player.is_winner && player.is_active && "bg-neutral text-neutral-content",
          player.is_winner && "bg-accent text-accent-content"
        ]}
      >
        <div class="text-center">{player.name}</div>
        <div class="text-center text-sm opacity-50 mb-2">
          <%= cond do %>
            <% player.is_dealer -> %>
              dealer
            <% true -> %>
              &nbsp;
          <% end %>
        </div>
        <div class="text-2xl text-center">
          {player.bet}
        </div>
        <%= if @game.state == :finished do %>
          <div class="m-4 flex flex-row gap-2 justify-center">
            <.card
              :for={%Card{suit: suit, rank: rank} <- player.cards}
              suit={suit}
              value={rank}
              width="50"
            />
          </div>
          <div class="text-center">
            <% {hand, _rank, _high} = Poker.find_best_hand(player.cards, @game.community_cards) %>
            {hand}
          </div>
        <% else %>
          <div class="m-4 flex flex-row gap-2 justify-center">
            <.card_back width="64" />
            <.card_back width="64" />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :game, Game, required: true
  attr :player, Player, required: true
  attr :action_form, Phoenix.HTML.Form, required: true

  defp player_pane(assigns) do
    ~H"""
    <div class="text-center text-xl m-8">{@player.name}</div>
    <div class="grid grid-cols-2 gap-4">
      <div>
        <div class="flex flex-row gap-2 justify-center m-8">
          <.card
            :for={%Card{suit: suit, rank: value} <- @player.cards}
            width="100"
            suit={suit}
            value={value}
          />
        </div>
        <div :if={@game.state == :waiting_for_players} class="flex flex-row gap-2 justify-center m-8">
          <div class="w-[100px] h-36 border border-dashed rounded"></div>
          <div class="w-[100px] h-36 border border-dashed rounded"></div>
        </div>
        <div :if={Enum.any?(@player.cards) && Enum.any?(@game.community_cards)} class="text-center">
          <% {hand, _rank, _high} = Poker.find_best_hand(@player.cards, @game.community_cards) %>

          {hand}
        </div>
      </div>
      <div>
        <div class="flex flex-row gap-4 p-8 m-8 rounded-box">
          <.form for={@action_form} phx-change="change-action" phx-submit="submit-action">
            <div :if={@game.round > 0}>
              <label>
                <input
                  type="radio"
                  name="player_action"
                  class="radio me-2"
                  value="check"
                  checked={@action_form[:player_action].value == "check"}
                  disabled={!@player.is_active}
                /> Check
              </label>
            </div>
            <div>
              <label>
                <input
                  type="radio"
                  name="player_action"
                  class="radio me-2"
                  value="call"
                  checked={@action_form[:player_action].value == "call"}
                  disabled={!@player.is_active}
                /> Call ({@game.bet})
              </label>
            </div>
            <div class="flex flex-row items-center">
              <label class="me-2">
                <input
                  type="radio"
                  name="player_action"
                  class="radio me-2"
                  value="raise"
                  checked={@action_form[:player_action].value == "raise"}
                  disabled={!@player.is_active}
                /> Raise
              </label>
              <.input
                field={@action_form[:raise_bet]}
                class="input w-32"
                type="number"
                min={Money.to_decimal(Money.mult!(@game.bet, 2))}
                disabled={!@player.is_active}
              />
            </div>
            <div>
              <label>
                <input
                  type="radio"
                  name="player_action"
                  class="radio me-2"
                  value="fold"
                  checked={@action_form[:player_action].value == "fold"}
                  disabled={!@player.is_active}
                /> Fold
              </label>
            </div>
            <button type="submit" class="btn btn-primary" disabled={!@player.is_active}>
              Submit
            </button>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  attr :suit, :atom, values: @suits, required: true
  attr :value, :integer, values: 1..13, required: true
  attr :rest, :global

  defp card(assigns) do
    suit =
      Atom.to_string(assigns.suit)
      |> String.upcase()
      |> String.slice(0..-2//1)

    value =
      case assigns.value do
        11 -> "11-JACK"
        12 -> "12-QUEEN"
        13 -> "13-KING"
        14 -> "1"
        v -> to_string(v)
      end

    assigns =
      Map.merge(assigns, %{
        suit: suit,
        value: value
      })

    ~H"""
    <img {@rest} src={"/images/cards/#{@suit}-#{@value}.svg"} />
    """
  end

  attr :style, :string, default: "plaid-blue"
  attr :rest, :global

  defp card_back(assigns) do
    ~H"""
    <img {@rest} src={"/images/backs/#{@style}.svg"} />
    """
  end

  def mount(%{"slug" => game_slug}, %{"player_id" => player_id}, socket) do
    game =
      Repo.get_by!(Game, slug: game_slug)
      |> Repo.preload([:players])

    player = Repo.get!(Player, player_id)

    PubSub.subscribe(Holdem.PubSub, "game:#{game.id}")

    socket =
      socket
      |> assign(%{
        player: player,
        scope: %Scope{player: player},
        game: game,
        action_form:
          to_form(%{
            "player_action" => nil,
            "raise_bet" => Money.mult!(game.bet, 2)
          })
      })

    {:ok, socket}
  end

  def handle_params(_unsigned_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_event("start-game", _params, socket) do
    {:ok, game} = Poker.start_game(socket.assigns.game.id, socket.assigns.scope)

    player =
      Repo.reload(socket.assigns.player)

    socket =
      socket
      |> assign(%{
        game: game,
        player: player
      })

    {:noreply, socket}
  end

  def handle_event("change-action", params, socket) do
    socket =
      socket
      |> assign(%{
        action_form: to_form(params)
      })

    {:noreply, socket}
  end

  def handle_event("submit-action", %{"player_action" => "call"}, socket) do
    {:ok, %{player: player, game: game}} =
      Poker.player_action_call(socket.assigns.scope.player.id, socket.assigns.scope)

    game = Repo.preload(game, [:players])

    socket =
      socket
      |> assign(%{
        game: game,
        player: player,
        scope: %Scope{player: player},
        action_form:
          to_form(%{
            "player_action" => nil,
            "raise_bet" => Money.mult!(socket.assigns.game.bet, 2)
          })
      })

    {:noreply, socket}
  end

  def handle_event("submit-action", %{"player_action" => "raise", "raise_bet" => bet}, socket) do
    {:ok, %{player: player, game: game}} =
      Poker.player_action_raise(
        socket.assigns.scope,
        socket.assigns.scope.player.id,
        Money.new!(socket.assigns.game.bet.currency, Decimal.new(bet))
      )

    game = Repo.preload(game, [:players])

    socket =
      socket
      |> assign(%{
        game: game,
        player: player,
        scope: %Scope{player: player},
        action_form:
          to_form(%{
            "player_action" => nil,
            "raise_bet" => Money.mult!(socket.assigns.game.bet, 2)
          })
      })

    {:noreply, socket}
  end

  def handle_event("submit-action", %{"player_action" => "check"}, socket) do
    {:ok, %{player: player, game: game}} =
      Poker.player_action_check(socket.assigns.scope, socket.assigns.scope.player.id)

    game = Repo.preload(game, [:players])

    socket =
      socket
      |> assign(%{
        game: game,
        player: player,
        scope: %Scope{player: player},
        action_form:
          to_form(%{
            "player_action" => nil,
            "raise_bet" => Money.mult!(socket.assigns.game.bet, 2)
          })
      })

    {:noreply, socket}
  end

  def handle_event("submit-action", %{"player_action" => "fold"}, socket) do
    {:ok, %{player: player, game: game}} =
      Poker.player_action_fold(socket.assigns.scope, socket.assigns.scope.player.id)

    game = Repo.preload(game, [:players])

    socket =
      socket
      |> assign(%{
        game: game,
        player: player,
        scope: %Scope{player: player},
        action_form:
          to_form(%{
            "player_action" => nil,
            "raise_bet" => Money.mult!(socket.assigns.game.bet, 2)
          })
      })

    {:noreply, socket}
  end

  def handle_info({:player_joined, _player_id}, socket) do
    game =
      Repo.reload!(socket.assigns.game)
      |> Repo.preload([:players])

    player =
      Repo.reload!(socket.assigns.player)

    socket =
      socket
      |> assign(%{
        game: game,
        player: player,
        scope: %Scope{player: player}
      })

    {:noreply, socket}
  end

  def handle_info(:game_started, socket) do
    game =
      Repo.reload!(socket.assigns.game)
      |> Repo.preload([:players])

    player =
      Repo.reload!(socket.assigns.player)

    socket =
      socket
      |> assign(%{
        game: game,
        player: player,
        scope: %Scope{player: player}
      })

    {:noreply, socket}
  end

  def handle_info(:player_action_taken, socket) do
    game =
      Repo.reload!(socket.assigns.game)
      |> Repo.preload([:players])

    player =
      Repo.reload!(socket.assigns.player)

    socket =
      socket
      |> assign(%{
        game: game,
        player: player,
        scope: %Scope{player: player}
      })

    {:noreply, socket}
  end
end
