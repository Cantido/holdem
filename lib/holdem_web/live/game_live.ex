defmodule HoldemWeb.GameLive do
  use HoldemWeb, :live_view

  @suits ~w(hearts diamonds spades clubs)a

  @big_blind_bet 2
  @player_count 5

  def render(assigns) do
    ~H"""
    <div :if={@round > 0} class="flex flex-row gap-2 m-4">
      <.card :for={{suit, value} <- @community_cards} width="100" suit={suit} value={value} />
    </div>
    <div
      :for={{player, i} <- Enum.with_index(@players)}
      class={[
        "flex flex-row gap-4 p-4",
        is_nil(@winner) && @player_under_the_gun == i && "bg-neutral text-neutral-content",
        @winner == i && "bg-accent text-accent-content"
      ]}
    >
      <div class="w-48">
        <div>Player {i + 1}</div>
        <div :if={i == @button_player}>dealer</div>
        <div :if={i == rem(@button_player + 1, Enum.count(@players))}>small blind</div>
        <div :if={i == rem(@button_player + 2, Enum.count(@players))}>big blind</div>
        <div>Bet: ${:erlang.float_to_binary(player.bet / 1.0, decimals: 0)}</div>
      </div>
      <%= if @round == 4 do %>
        <.card :for={{suit, value} <- player.cards} width="100" suit={suit} value={value} />
      <% else %>
        <.card_back :for={_card <- player.cards} width="100" />
      <% end %>
      <%= if @round < 4 do %>
        <div :if={@player_under_the_gun == i}>
          <.form for={@action_form} phx-change="change-action" phx-submit="submit-action">
            <input type="hidden" name="player_id" value={@player_under_the_gun} />
            <div :if={@round > 0}>
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
                /> Call (${@big_blind_bet})
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
                min={@big_blind_bet * 2}
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

  def mount(_params, _session, socket) do
    deck =
      for suit <- ~w(hearts diamonds spades clubs)a, num <- 2..14 do
        {suit, num}
      end
      |> Enum.shuffle()

    {players, deck} =
      Enum.reduce(1..@player_count, {[], deck}, fn _i, {players, deck} ->
        {hole_cards, deck} = take_from_deck(deck, 2)

        {players ++ [%{cards: hole_cards, bet: 0}], deck}
      end)

    players =
      players
      |> List.update_at(1, fn player ->
        Map.put(player, :bet, @big_blind_bet / 2)
      end)
      |> List.update_at(2, fn player ->
        Map.put(player, :bet, @big_blind_bet)
      end)

    socket =
      socket
      |> assign(%{
        players: players,
        button_player: 0,
        deck: deck,
        round: 0,
        big_blind_bet: @big_blind_bet,
        player_under_the_gun: 3,
        community_cards: [],
        winner: nil,
        action_form: to_form(%{"player_action" => nil, "raise_bet" => @big_blind_bet * 2})
      })

    {:ok, socket}
  end

  def handle_event("change-action", params, socket) do
    socket =
      socket
      |> assign(%{
        action_form: to_form(params)
      })

    {:noreply, socket}
  end

  def handle_event("submit-action", %{"player_action" => "call"} = params, socket) do
    players =
      socket.assigns.players
      |> List.update_at(socket.assigns.player_under_the_gun, fn player ->
        Map.update!(player, :bet, fn bet -> bet + socket.assigns.big_blind_bet end)
      end)

    socket =
      socket
      |> assign(%{
        players: players
      })

    socket = next_player(socket)

    {:noreply, socket}
  end

  def handle_event("submit-action", %{"player_action" => "raise"} = params, socket) do
    players =
      socket.assigns.players
      |> List.update_at(socket.assigns.player_under_the_gun, fn player ->
        Map.update!(player, :bet, fn bet -> bet + String.to_integer(params["raise_bet"]) end)
      end)

    socket =
      socket
      |> assign(%{
        players: players
      })

    socket = next_player(socket)

    {:noreply, socket}
  end

  def handle_event("submit-action", %{"player_action" => "check"} = params, socket) do
    socket = next_player(socket)

    {:noreply, socket}
  end

  def handle_event("submit-action", %{"player_action" => "fold"} = params, socket) do
    players =
      socket.assigns.players
      |> List.update_at(socket.assigns.player_under_the_gun, fn player ->
        Map.put(player, :folded?, true)
      end)

    socket = next_player(socket)

    {:noreply, socket}
  end

  defp next_player(socket) do
    first_player_id =
      rem(socket.assigns.button_player + 1, Enum.count(socket.assigns.players))

    player_count = Enum.count(socket.assigns.players)

    {later, sooner} =
      0..(player_count - 1)
      |> Enum.split(socket.assigns.button_player + 1)

    player_sequence = sooner ++ later

    remaining_players =
      player_sequence
      |> Enum.drop_while(fn i -> i != socket.assigns.player_under_the_gun end)
      |> Enum.drop(1)
      |> Enum.reject(fn i ->
        player = Enum.at(socket.assigns.players, i)
        player[:folded?]
      end)

    next_player_id =
      if Enum.empty?(remaining_players) do
        player_sequence
        |> Enum.reject(fn i ->
          player = Enum.at(socket.assigns.players, i)
          player[:folded?]
        end)
        |> List.first()
      else
        List.first(remaining_players)
      end

    socket =
      if next_player_id == first_player_id do
        socket =
          assign(socket, :round, socket.assigns.round + 1)

        socket =
          if socket.assigns.round == 1 do
            {cards, deck} = take_from_deck(socket.assigns.deck, 3)

            assign(socket, %{
              community_cards: cards,
              deck: deck
            })
          else
            socket
          end

        socket =
          if socket.assigns.round in [2, 3] do
            {cards, deck} = take_from_deck(socket.assigns.deck, 1)

            assign(socket, %{
              community_cards: socket.assigns.community_cards ++ cards,
              deck: deck
            })
          else
            socket
          end

        socket =
          if socket.assigns.round == 4 do
            players =
              Enum.with_index(socket.assigns.players)
              |> Enum.map(fn {player, player_id} ->
                {hand, rank, high_value} =
                  find_best_hand(player.cards, socket.assigns.community_cards)

                Map.merge(player, %{
                  hand: hand,
                  hand_rank: rank,
                  hand_high_value: high_value
                })
              end)

            socket = assign(socket, :players, players)

            {_winner, winner_id} =
              Enum.with_index(socket.assigns.players)
              |> Enum.max(fn {a, _i}, {b, _j} ->
                if a.hand_rank == b.hand_rank do
                  a.hand_high_value >= b.hand_high_value
                else
                  a.hand_rank >= b.hand_rank
                end
              end)

            assign(socket, :winner, winner_id)
          else
            socket
          end
      else
        socket
      end

    socket =
      assign(
        socket,
        %{
          player_under_the_gun: next_player_id,
          action_form: to_form(%{"player_action" => nil, "raise_bet" => @big_blind_bet * 2})
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
      left_to_fix = count_to_pick - Enum.count(stem) + 1

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
    Enum.max_by(cards, fn {_suit, value} ->
      value
    end)
    |> elem(0)
  end

  defp high_card(:four_of_a_kind, cards) do
    Enum.group_by(cards, fn {_suit, rank} -> rank end)
    |> Enum.find(fn {_rank, rank_cards} -> Enum.count(rank_cards) == 4 end)
    |> elem(1)
    |> Enum.max_by(fn {_suit, rank} -> rank end)
    |> elem(0)
  end

  defp high_card(:full_house, cards) do
    Enum.group_by(cards, fn {_suit, rank} -> rank end)
    |> Enum.find(fn {_rank, rank_cards} -> Enum.count(rank_cards) == 3 end)
    |> elem(1)
    |> Enum.max_by(fn {_suit, rank} -> rank end)
    |> elem(0)
  end

  defp high_card(:three_of_a_kind, cards) do
    Enum.group_by(cards, fn {_suit, rank} -> rank end)
    |> Enum.find(fn {_rank, rank_cards} -> Enum.count(rank_cards) == 3 end)
    |> elem(1)
    |> Enum.max_by(fn {_suit, rank} -> rank end)
    |> elem(0)
  end

  defp high_card(:two_pair, cards) do
    Enum.group_by(cards, fn {_suit, rank} -> rank end)
    |> Enum.filter(fn {_rank, rank_cards} -> Enum.count(rank_cards) == 2 end)
    |> List.flatten()
    |> Enum.max_by(fn {_suit, rank} -> rank end)
    |> elem(0)
  end

  defp high_card(:one_pair, cards) do
    Enum.group_by(cards, fn {_suit, rank} -> rank end)
    |> Enum.filter(fn {_rank, rank_cards} -> Enum.count(rank_cards) == 2 end)
    |> List.flatten()
    |> Enum.max_by(fn {_suit, rank} -> rank end)
    |> elem(0)
  end

  defp high_card(_, cards) do
    Enum.max_by(cards, fn {_suit, value} ->
      value
    end)
    |> elem(0)
  end

  defp royal_flush?(cards) do
    {suit, _value} = List.first(cards)

    Enum.all?(cards, fn {s, _v} -> s == suit end) &&
      Enum.member?(cards, {suit, 10}) &&
      Enum.member?(cards, {suit, 11}) &&
      Enum.member?(cards, {suit, 12}) &&
      Enum.member?(cards, {suit, 13}) &&
      Enum.member?(cards, {suit, 1})
  end

  defp straight_flush?(cards) do
    straight?(cards) && flush?(cards)
  end

  defp four_of_a_kind?(cards) do
    freqs =
      Enum.frequencies_by(cards, fn {_suit, rank} -> rank end)
      |> Map.values()

    4 in freqs
  end

  defp full_house?(cards) do
    freqs =
      Enum.frequencies_by(cards, fn {_suit, rank} -> rank end)
      |> Map.values()
      |> Enum.sort()

    freqs == [2, 3]
  end

  defp flush?(cards) do
    {suit, _value} = List.first(cards)

    Enum.all?(cards, fn {s, _v} -> s == suit end)
  end

  defp straight?(cards) do
    [first, second, third, fourth, fifth] =
      Enum.map(cards, fn {_suit, rank} ->
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
      Enum.frequencies_by(cards, fn {_suit, rank} -> rank end)
      |> Map.values()

    3 in freqs
  end

  defp two_pair?(cards) do
    freqs =
      Enum.frequencies_by(cards, fn {_suit, rank} -> rank end)
      |> Map.values()
      |> Enum.sort()

    freqs == [2, 2, 1]
  end

  defp one_pair?(cards) do
    freqs =
      Enum.frequencies_by(cards, fn {_suit, rank} -> rank end)
      |> Map.values()
      |> Enum.sort()

    freqs == [2, 1, 1, 1]
  end
end
