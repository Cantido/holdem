defmodule HoldemWeb.GameLive do
  alias Phoenix.PubSub
  alias Holdem.Repo
  use HoldemWeb, :live_view

  alias Holdem.Card
  alias Holdem.Poker.Game
  alias Holdem.Poker.Player

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
    Enum.reduce(enum, Decimal.new(0), fn x, acc -> Decimal.add(acc, x) end)
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
        ${Decimal.to_string(decimal_sum(Enum.map(@game.players, fn p -> p.bet end)), :normal)}
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
          "w-32 h-32 p-2",
          player.is_folded && "bg-base-200",
          !player.is_winner && player.is_under_the_gun && "bg-neutral text-neutral-content",
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
          ${Decimal.to_string(player.bet, :normal)}
        </div>
        <div :if={player.is_winner} class="text-xl text-center">
          Winner!
        </div>
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
          <% {hand, _rank, _high} = find_best_hand(@player.cards, @game.community_cards) %>

          {hand}
        </div>
      </div>
      <div>
        <div class={[
          "flex flex-row gap-4 p-8 m-8 rounded-box",
          @player.is_folded && "bg-base-200",
          !@player.is_winner && @player.is_under_the_gun && "bg-neutral text-neutral-content",
          @player.is_winner && "bg-accent text-accent-content"
        ]}>
          <.form for={@action_form} phx-change="change-action" phx-submit="submit-action">
            <div :if={@game.round > 0}>
              <label>
                <input
                  type="radio"
                  name="player_action"
                  class="radio me-2"
                  value="check"
                  checked={@action_form[:player_action].value == "check"}
                  disabled={!@player.is_under_the_gun}
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
                  disabled={!@player.is_under_the_gun}
                /> Call (${@game.big_blind})
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
                  disabled={!@player.is_under_the_gun}
                /> Raise
              </label>
              <.input
                field={@action_form[:raise_bet]}
                class="input w-32"
                type="number"
                min={Decimal.mult(@game.big_blind, 2)}
                disabled={!@player.is_under_the_gun}
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
                  disabled={!@player.is_under_the_gun}
                /> Fold
              </label>
            </div>
            <button type="submit" class="btn btn-primary" disabled={!@player.is_under_the_gun}>
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

  def mount(_params, %{"player_id" => player_id}, socket) do
    player = Repo.get!(Player, player_id)

    socket =
      socket
      |> assign(%{
        player: player,
        game: nil,
        winner: nil,
        action_form: nil
      })

    {:ok, socket}
  end

  def handle_params(unsigned_params, _uri, socket) do
    if game_id = unsigned_params["id"] do
      game =
        Repo.get!(Game, game_id)
        |> Repo.preload([:players])

      PubSub.subscribe(Holdem.PubSub, "game:#{game.id}")

      socket =
        socket
        |> assign(%{
          game: game,
          action_form:
            to_form(%{"player_action" => nil, "raise_bet" => Decimal.mult(game.big_blind, 2)})
        })

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("start-game", _params, socket) do
    {:ok, game} =
      Repo.transaction(fn ->
        if Enum.count(socket.assigns.game.players) < 3 do
          raise "TODO: Less than three players is a special case!"
        end

        game =
          socket.assigns.game
          |> Ecto.Changeset.change(%{
            state: :playing
          })
          |> Repo.update!()
          |> Repo.preload(:players)

        Enum.each(game.players, fn %Player{} = player ->
          game = Repo.reload!(game)

          {cards, deck} = Card.take_from_deck(game.deck, 2)

          player
          |> Ecto.Changeset.change(%{
            cards: cards
          })
          |> Repo.update!()

          game
          |> Ecto.Changeset.change(%{
            deck: deck
          })
          |> Repo.update!()
        end)

        game =
          Repo.preload(game, :players)

        dealer_pos =
          Enum.find(game.players, & &1.is_dealer)
          |> Map.get(:position)

        small_blind_pos =
          rem(dealer_pos + 1, Enum.count(game.players))

        Enum.find(game.players, &(&1.position == small_blind_pos))
        |> Ecto.Changeset.change(%{
          bet: Decimal.div(game.big_blind, 2) |> Decimal.round(2)
        })
        |> Repo.update!()

        big_blind_pos =
          rem(small_blind_pos + 1, Enum.count(game.players))

        Enum.find(game.players, &(&1.position == big_blind_pos))
        |> Ecto.Changeset.change(%{
          bet: game.big_blind
        })
        |> Repo.update!()

        first_player_pos =
          rem(big_blind_pos + 1, Enum.count(game.players))

        Enum.find(game.players, &(&1.position == first_player_pos))
        |> Ecto.Changeset.change(%{
          is_under_the_gun: true
        })
        |> Repo.update!()

        Repo.reload!(game)
        |> Repo.preload(:players)
      end)

    player =
      Repo.reload(socket.assigns.player)

    socket =
      socket
      |> assign(%{
        game: game,
        player: player
      })

    PubSub.broadcast(Holdem.PubSub, "game:#{game.id}", :game_started)

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
    socket.assigns.game.players
    |> Enum.find(& &1.is_under_the_gun)
    |> then(fn player ->
      Ecto.Changeset.change(player, %{
        bet: Decimal.add(player.bet, socket.assigns.game.big_blind)
      })
    end)
    |> Repo.update!()

    game =
      Repo.reload!(socket.assigns.game)
      |> Repo.preload([:players])

    socket =
      socket
      |> assign(%{
        game: game
      })

    socket = next_player(socket)

    PubSub.broadcast(Holdem.PubSub, "game:#{game.id}", :player_action_taken)

    {:noreply, socket}
  end

  def handle_event("submit-action", %{"player_action" => "raise"} = params, socket) do
    socket.assigns.game.players
    |> Enum.find(& &1.is_under_the_gun)
    |> then(fn player ->
      Ecto.Changeset.change(player, %{
        bet: Decimal.add(player.bet, Decimal.new(params["raise_bet"]))
      })
    end)
    |> Repo.update!()

    game =
      Repo.reload!(socket.assigns.game)
      |> Repo.preload([:players])

    socket =
      socket
      |> assign(%{
        game: game
      })

    socket = next_player(socket)

    PubSub.broadcast(Holdem.PubSub, "game:#{game.id}", :player_action_taken)

    {:noreply, socket}
  end

  def handle_event("submit-action", %{"player_action" => "check"}, socket) do
    socket = next_player(socket)

    PubSub.broadcast(Holdem.PubSub, "game:#{socket.assigns.game.id}", :player_action_taken)

    {:noreply, socket}
  end

  def handle_event("submit-action", %{"player_action" => "fold"}, socket) do
    socket.assigns.game.players
    |> Enum.find(& &1.is_under_the_gun)
    |> then(fn player ->
      Ecto.Changeset.change(player, %{
        is_folded: true
      })
    end)
    |> Repo.update!()

    game =
      Repo.reload!(socket.assigns.game)
      |> Repo.preload([:players])

    socket =
      socket
      |> assign(%{
        game: game
      })

    socket = next_player(socket)

    PubSub.broadcast(Holdem.PubSub, "game:#{game.id}", :player_action_taken)

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
        player: player
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
        player: player
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
        player: player
      })

    {:noreply, socket}
  end

  defp next_player(socket) do
    game = socket.assigns.game
    players = socket.assigns.game.players
    player_count = Enum.count(players)

    dealer_pos = Enum.find(players, & &1.is_dealer).position
    current_pos = Enum.find(players, & &1.is_under_the_gun).position

    {later, sooner} =
      0..(player_count - 1)
      |> Enum.split(dealer_pos + 1)

    player_sequence = sooner ++ later

    remaining_players =
      player_sequence
      |> Enum.drop_while(fn i -> i != current_pos end)
      |> Enum.drop(1)
      |> Enum.reject(fn i ->
        player = Enum.at(players, i)
        player.is_folded
      end)

    {next_player_pos, round_over} =
      if Enum.empty?(remaining_players) do
        pos =
          player_sequence
          |> Enum.reject(fn i ->
            player = Enum.at(players, i)
            player.is_folded
          end)
          |> List.first()

        {pos, true}
      else
        pos = List.first(remaining_players)
        {pos, false}
      end

    socket =
      if round_over do
        game =
          Ecto.Changeset.change(game, %{round: game.round + 1})
          |> Repo.update!()
          |> Repo.preload([:players])

        socket =
          if game.round == 1 do
            {cards, deck} = take_from_deck(game.deck, 3)

            game =
              game
              |> Ecto.Changeset.change(%{
                community_cards: cards,
                deck: deck
              })
              |> Repo.update!()
              |> Repo.preload([:players])

            assign(socket, :game, game)
          else
            socket
          end

        socket =
          if game.round in [2, 3] do
            {cards, deck} = take_from_deck(game.deck, 1)

            game =
              game
              |> Ecto.Changeset.change(%{
                community_cards: game.community_cards ++ cards,
                deck: deck
              })
              |> Repo.update!()
              |> Repo.preload([:players])

            assign(socket, :game, game)
          else
            socket
          end

        socket =
          if game.round == 4 do
            player_hands =
              players
              |> Map.new(fn player ->
                {hand, rank, high_value} =
                  find_best_hand(player.cards, socket.assigns.game.community_cards)

                {player.id,
                 %{
                   hand: hand,
                   hand_rank: rank,
                   hand_high_value: high_value
                 }}
              end)

            socket = assign(socket, :player_hands, player_hands)

            {winner_id, _winning_hand} =
              Enum.max(player_hands, fn {_i, a}, {_j, b} ->
                if a.hand_rank == b.hand_rank do
                  a.hand_high_value >= b.hand_high_value
                else
                  a.hand_rank >= b.hand_rank
                end
              end)

            players
            |> Enum.find(&(&1.id == winner_id))
            |> Ecto.Changeset.change(%{is_winner: true})
            |> Repo.update!()

            game =
              Repo.reload!(game)
              |> Repo.preload([:players])

            assign(socket, :game, game)
          else
            socket
          end

        socket
      else
        socket
      end

    Repo.transaction(fn ->
      Enum.find(players, & &1.is_under_the_gun)
      |> Ecto.Changeset.change(%{
        is_under_the_gun: false
      })
      |> Repo.update!()

      Enum.find(players, &(&1.position == next_player_pos))
      |> Ecto.Changeset.change(%{
        is_under_the_gun: true
      })
      |> Repo.update!()
    end)

    game =
      Repo.reload!(game)
      |> Repo.preload([:players])

    player =
      Repo.reload!(socket.assigns.player)

    socket =
      assign(
        socket,
        %{
          game: game,
          player: player,
          action_form:
            to_form(%{
              "player_action" => nil,
              "raise_bet" => Decimal.mult(socket.assigns.game.big_blind, 2)
            })
        }
      )

    socket
  end

  defp take_from_deck(deck, count) do
    Enum.reduce(1..count, {[], deck}, fn _i, {cards, deck} ->
      {card, deck} = List.pop_at(deck, 0)

      {cards ++ [card], deck}
    end)
  end

  defp find_best_hand(player_cards, community_cards) do
    combinations(community_cards, 3)
    |> Enum.map(fn combination ->
      player_cards ++ combination
    end)
    |> Enum.map(&identify_hand/1)
    |> Enum.max(fn {_a_hand, a_rank, a_high}, {_b_hand, b_rank, b_high} ->
      if a_rank == b_rank do
        a_high >= b_high
      else
        a_rank >= b_rank
      end
    end)
  end

  def combinations(cards, count_to_pick) do
    count_to_fix = Enum.count(cards) - count_to_pick + 1

    cards
    |> Enum.take(count_to_fix)
    |> Enum.with_index()
    |> Enum.flat_map(fn {fixed_card, index_to_fix} ->
      remaining = Enum.drop(cards, index_to_fix + 1)
      do_combinations([fixed_card], remaining, count_to_pick)
    end)
  end

  def do_combinations(stem, remaining, count_to_pick) do
    if Enum.count(stem) == count_to_pick do
      [stem]
    else
      remaining
      |> Enum.with_index()
      |> Enum.flat_map(fn {next_fixed, index_to_fix} ->
        remaining = Enum.drop(remaining, index_to_fix + 1)
        do_combinations(stem ++ [next_fixed], remaining, count_to_pick)
      end)
    end
  end

  defp identify_hand(cards) do
    cond do
      royal_flush?(cards) ->
        {:royal_flush, 9, 14}

      straight_flush?(cards) ->
        {:straight_flush, 8, high_card(:straight_flush, cards)}

      four_of_a_kind?(cards) ->
        {:four_of_a_kind, 7, high_card(:four_of_a_kind, cards)}

      full_house?(cards) ->
        {:full_house, 6, high_card(:full_house, cards)}

      flush?(cards) ->
        {:flush, 5, high_card(:flush, cards)}

      straight?(cards) ->
        {:straight, 4, high_card(:straight, cards)}

      three_of_a_kind?(cards) ->
        {:three_of_a_kind, 3, high_card(:three_of_a_kind, cards)}

      two_pair?(cards) ->
        {:two_pair, 2, high_card(:two_pair, cards)}

      one_pair?(cards) ->
        {:one_pair, 1, high_card(:one_pair, cards)}

      true ->
        {:high_card, 0, high_card(:high_card, cards)}
    end
  end

  defp high_card(:straight_flush, cards) do
    Enum.max_by(cards, fn %Card{rank: rank} ->
      rank
    end)
  end

  defp high_card(:four_of_a_kind, cards) do
    Enum.group_by(cards, fn %Card{rank: rank} -> rank end)
    |> Enum.find(fn {_rank, rank_cards} -> Enum.count(rank_cards) == 4 end)
    |> elem(1)
    |> Enum.max_by(fn %Card{rank: rank} -> rank end)
    |> Map.get(:rank)
  end

  defp high_card(:full_house, cards) do
    Enum.group_by(cards, fn %Card{rank: rank} -> rank end)
    |> Enum.find(fn {_rank, rank_cards} -> Enum.count(rank_cards) == 3 end)
    |> elem(1)
    |> Enum.max_by(fn %Card{rank: rank} -> rank end)
    |> Map.get(:rank)
  end

  defp high_card(:three_of_a_kind, cards) do
    Enum.group_by(cards, fn %Card{rank: rank} -> rank end)
    |> Enum.find(fn {_rank, rank_cards} -> Enum.count(rank_cards) == 3 end)
    |> elem(1)
    |> Enum.max_by(fn %Card{rank: rank} -> rank end)
    |> Map.get(:rank)
  end

  defp high_card(:two_pair, cards) do
    Enum.group_by(cards, fn %Card{rank: rank} -> rank end)
    |> Enum.filter(fn {_rank, rank_cards} -> Enum.count(rank_cards) == 2 end)
    |> List.flatten()
    |> Enum.max_by(fn {rank, _cards} -> rank end)
    |> elem(0)
  end

  defp high_card(:one_pair, cards) do
    Enum.group_by(cards, fn %Card{rank: rank} -> rank end)
    |> Enum.filter(fn {_rank, rank_cards} -> Enum.count(rank_cards) == 2 end)
    |> List.flatten()
    |> Enum.max_by(fn {rank, _cards} -> rank end)
    |> elem(0)
  end

  defp high_card(_, cards) do
    Enum.max_by(cards, fn %Card{rank: rank} ->
      rank
    end)
    |> Map.get(:rank)
  end

  defp royal_flush?(cards) do
    %Card{suit: suit} = List.first(cards)

    Enum.all?(cards, fn %Card{suit: s} -> s == suit end) &&
      Enum.member?(cards, %Card{suit: suit, rank: 10}) &&
      Enum.member?(cards, %Card{suit: suit, rank: 11}) &&
      Enum.member?(cards, %Card{suit: suit, rank: 12}) &&
      Enum.member?(cards, %Card{suit: suit, rank: 13}) &&
      Enum.member?(cards, %Card{suit: suit, rank: 14})
  end

  defp straight_flush?(cards) do
    straight?(cards) && flush?(cards)
  end

  defp four_of_a_kind?(cards) do
    freqs =
      Enum.frequencies_by(cards, fn %Card{rank: rank} -> rank end)
      |> Map.values()

    4 in freqs
  end

  defp full_house?(cards) do
    freqs =
      Enum.frequencies_by(cards, fn %Card{rank: rank} -> rank end)
      |> Map.values()
      |> Enum.sort()

    freqs == [2, 3]
  end

  defp flush?(cards) do
    %Card{suit: suit} = List.first(cards)

    Enum.all?(cards, fn %Card{suit: s} -> s == suit end)
  end

  defp straight?(cards) do
    [first, second, third, fourth, fifth] =
      Enum.map(cards, fn %Card{rank: rank} ->
        rank
      end)
      |> Enum.sort()

    first + 1 == second &&
      second + 1 == third &&
      third + 1 == fourth &&
      fourth + 1 == fifth
  end

  defp three_of_a_kind?(cards) do
    freqs =
      Enum.frequencies_by(cards, fn %Card{rank: rank} -> rank end)
      |> Map.values()

    3 in freqs
  end

  defp two_pair?(cards) do
    freqs =
      Enum.frequencies_by(cards, fn %Card{rank: rank} -> rank end)
      |> Map.values()
      |> Enum.sort()

    freqs == [1, 2, 2]
  end

  defp one_pair?(cards) do
    freqs =
      Enum.frequencies_by(cards, fn %Card{rank: rank} -> rank end)
      |> Map.values()
      |> Enum.sort()
      |> dbg()

    freqs == [1, 1, 1, 2]
  end
end
