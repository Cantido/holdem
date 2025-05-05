defmodule HoldemWeb.GameLive do
  alias Holdem.Repo
  use HoldemWeb, :live_view

  alias Holdem.Card
  alias Holdem.Poker.Game
  alias Holdem.Poker.Player

  @suits ~w(hearts diamonds spades clubs)a

  def render(assigns) do
    ~H"""
    <%= if is_nil(@game) do %>
      <form phx-submit="new-game">
        <input type="number" min="0" name="big-blind" />
        <button type="submit" class="btn btn-primary">New Game</button>
      </form>
    <% else %>
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
      <div class="flex flex-row justify-center">
        <div
          :for={{player, i} <- Enum.with_index(@game.players)}
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
      <div
        :for={{player, i} <- Enum.with_index(@game.players)}
        class={[
          "flex flex-row gap-4 p-4",
          player.is_folded && "bg-base-200",
          !player.is_winner && player.is_under_the_gun && "bg-neutral text-neutral-content",
          player.is_winner && "bg-accent text-accent-content"
        ]}
      >
        <%= if @round < 4 do %>
          <div :if={player.is_under_the_gun}>
            <.form for={@action_form} phx-change="change-action" phx-submit="submit-action">
              <div :if={@game.round > 0}>
                <label>
                  <input
                    type="radio"
                    name="player_action"
                    class="radio me-2"
                    value="check"
                    checked={@action_form[:player_action].value == "check"}
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
                  /> Raise
                </label>
                <.input
                  field={@action_form[:raise_bet]}
                  class="input w-32"
                  type="number"
                  min={Decimal.mult(@game.big_blind, 2)}
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
                  /> Fold
                </label>
              </div>
              <button type="submit" class="btn btn-primary">Submit</button>
            </.form>
          </div>
        <% else %>
          <div :if={@winner == i}>
            WINNER! {player.hand}
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp decimal_sum(enum) do
    Enum.reduce(enum, Decimal.new(0), fn x, acc -> Decimal.add(acc, x) end)
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

  def mount(_params, _session, socket) do
    deck =
      for suit <- ~w(hearts diamonds spades clubs)a, num <- 2..14 do
        {suit, num}
      end
      |> Enum.shuffle()

    socket =
      socket
      |> assign(%{
        game: nil,
        deck: deck,
        round: 0,
        player_under_the_gun: 3,
        winner: nil,
        action_form: nil
      })

    {:ok, socket}
  end

  def handle_params(unsigned_params, _uri, socket) do
    if game_id = unsigned_params["id"] do
      game =
        Repo.get(Game, game_id)
        |> Repo.preload([:players])

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

  def handle_event("new-game", params, socket) do
    {:ok, game} =
      Repo.transaction(fn ->
        big_blind = Decimal.new(params["big-blind"])

        game =
          %Game{}
          |> Ecto.Changeset.change(%{
            big_blind: big_blind,
            community_cards: [],
            deck: Card.deck() |> Enum.shuffle()
          })
          |> Repo.insert!()

        Enum.each(1..5, fn i ->
          game = Repo.get(Game, game.id)

          {cards, deck} = take_from_deck(game.deck, 2)

          Ecto.Changeset.change(game, %{deck: deck})
          |> Repo.update!()

          %Player{
            name: "Player #{i}",
            game_id: game.id,
            cards: cards,
            position: i - 1,
            is_dealer: i == 1,
            bet:
              case i do
                2 -> Decimal.div(big_blind, 2) |> Decimal.round(2)
                3 -> big_blind
                _ -> Decimal.new(0)
              end,
            is_under_the_gun: i == 4
          }
          |> Ecto.Changeset.change(%{})
          |> Repo.insert!()
        end)

        game
      end)

    socket =
      socket
      |> push_patch(to: "/game/#{game.id}")

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

    {:noreply, socket}
  end

  def handle_event("submit-action", %{"player_action" => "check"}, socket) do
    socket = next_player(socket)

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

    {:noreply, socket}
  end

  defp next_player(socket) do
    game = socket.assigns.game
    players = socket.assigns.game.players
    player_count = Enum.count(players)

    dealer_pos = Enum.find(players, & &1.is_dealer).position
    current_pos = Enum.find(players, & &1.is_under_the_gun).position

    first_player_id =
      rem(dealer_pos + 1, player_count)

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

    socket =
      assign(
        socket,
        %{
          game: game,
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
    |> Enum.max_by(fn %Card{rank: rank} -> rank end)
    |> Map.get(:rank)
  end

  defp high_card(:one_pair, cards) do
    Enum.group_by(cards, fn %Card{rank: rank} -> rank end)
    |> Enum.filter(fn {_rank, rank_cards} -> Enum.count(rank_cards) == 2 end)
    |> List.flatten()
    |> Enum.max_by(fn %Card{rank: rank} -> rank end)
    |> Map.get(:rank)
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

    freqs == [2, 2, 1]
  end

  defp one_pair?(cards) do
    freqs =
      Enum.frequencies_by(cards, fn %Card{rank: rank} -> rank end)
      |> Map.values()
      |> Enum.sort()

    freqs == [2, 1, 1, 1]
  end
end
