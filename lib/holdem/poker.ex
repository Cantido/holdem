defmodule Holdem.Poker do
  alias Holdem.Poker.Game
  alias Holdem.Poker.Player
  alias Holdem.Card
  alias Holdem.Repo
  alias Phoenix.PubSub

  def create_game(params) do
    %Game{}
    |> Ecto.Changeset.change(%{
      community_cards: [],
      deck: Card.deck() |> Enum.shuffle()
    })
    |> Game.changeset(params)
    |> Repo.insert()
  end

  def create_player(game_id, params) do
    Repo.get!(Game, game_id)
    |> Ecto.build_assoc(:players)
    |> Player.changeset(params)
    |> Repo.insert()
  end

  def start_game(game_id, scope) do
    if scope.player.is_dealer do
      Repo.transaction(fn ->
        game =
          Repo.get!(Game, game_id)
          |> Repo.preload(:players)

        if Enum.count(game.players) < 3 do
          raise "TODO: Less than three players is a special case!"
        end

        game =
          game
          |> Ecto.Changeset.change(%{
            state: :playing
          })
          |> Repo.update!()
          |> Repo.preload(:players)

        Enum.each(game.players, fn player ->
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
          Repo.reload!(game)
          |> Repo.preload(:players)

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
      |> case do
        {:ok, game} ->
          PubSub.broadcast(Holdem.PubSub, "game:#{game.id}", :game_started)
          {:ok, game}

        err ->
          err
      end
    else
      {:error, :unauthorized}
    end
  end

  def player_action_call(player_id, scope) do
    if scope.player.id == player_id do
      player = Repo.get!(Player, player_id)
      game = Repo.get!(Game, player.game_id)

      if player.is_under_the_gun do
        Ecto.Changeset.change(player, %{
          bet: Decimal.add(player.bet, game.big_blind)
        })
        |> Repo.update()
      else
        {:error, :not_your_turn}
      end
      |> case do
        {:ok, player} ->
          {:ok, game} = activate_next_player(scope, player.game_id)
          PubSub.broadcast(Holdem.PubSub, "game:#{player.game_id}", :player_action_taken)
          {:ok, %{player: player, game: game}}

        err ->
          err
      end
    else
      {:error, :unauthorized}
    end
  end

  def player_action_raise(scope, player_id, %Decimal{} = bet) do
    if scope.player.id == player_id do
      player = Repo.get!(Player, player_id)

      if player.is_under_the_gun do
        Ecto.Changeset.change(player, %{
          bet: Decimal.add(player.bet, bet)
        })
        |> Repo.update()
      else
        {:error, :not_your_turn}
      end
      |> case do
        {:ok, player} ->
          {:ok, game} = activate_next_player(scope, player.game_id)

          PubSub.broadcast(Holdem.PubSub, "game:#{player.game_id}", :player_action_taken)

          {:ok, %{player: player, game: game}}

        err ->
          err
      end
    else
      {:error, :unauthorized}
    end
  end

  def player_action_check(scope, player_id) do
    if scope.player.id == player_id do
      player = Repo.get!(Player, player_id)

      if player.is_under_the_gun do
        {:ok, game} = activate_next_player(scope, player.game_id)

        PubSub.broadcast(Holdem.PubSub, "game:#{player.game_id}", :player_action_taken)

        {:ok, %{player: player, game: game}}
      else
        {:error, :not_your_turn}
      end
    else
      {:error, :unauthorized}
    end
  end

  def player_action_fold(scope, player_id) do
    if scope.player.id == player_id do
      player = Repo.get!(Player, player_id)

      if player.is_under_the_gun do
        Ecto.Changeset.change(player, %{
          is_folded: true
        })
        |> Repo.update()
        |> case do
          {:ok, player} ->
            {:ok, game} = activate_next_player(scope, player.game_id)
            PubSub.broadcast(Holdem.PubSub, "game:#{player.game_id}", :player_action_taken)

            {:ok, %{player: player, game: game}}

          err ->
            err
        end
      else
        {:error, :not_your_turn}
      end
    else
      {:error, :unauthorized}
    end
  end

  def activate_next_player(scope, game_id) do
    current_player = Repo.get(Player, scope.player.id)

    if current_player.is_under_the_gun do
      game =
        Repo.get!(Game, game_id)
        |> Repo.preload(:players)

      players = game.players
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

      if round_over do
        game =
          Ecto.Changeset.change(game, %{round: game.round + 1})
          |> Repo.update!()

        if game.round == 1 do
          {cards, deck} = Card.take_from_deck(game.deck, 3)

          game
          |> Ecto.Changeset.change(%{
            community_cards: cards,
            deck: deck
          })
          |> Repo.update!()
        end

        if game.round in [2, 3] do
          {cards, deck} = Card.take_from_deck(game.deck, 1)

          game
          |> Ecto.Changeset.change(%{
            community_cards: game.community_cards ++ cards,
            deck: deck
          })
          |> Repo.update!()
        end

        if game.round == 4 do
          player_hands =
            players
            |> Map.new(fn player ->
              {hand, rank, high_value} =
                find_best_hand(player.cards, game.community_cards)

              {player.id,
               %{
                 hand: hand,
                 hand_rank: rank,
                 hand_high_value: high_value
               }}
            end)

          # TODO: detect a tie
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
        end
      end

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

      game = Repo.get(Game, game_id)

      {:ok, game}
    else
      {:error, :unauthorized}
    end
  end

  def find_best_hand(player_cards, community_cards) do
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

  defp combinations(cards, count_to_pick) do
    count_to_fix = Enum.count(cards) - count_to_pick + 1

    cards
    |> Enum.take(count_to_fix)
    |> Enum.with_index()
    |> Enum.flat_map(fn {fixed_card, index_to_fix} ->
      remaining = Enum.drop(cards, index_to_fix + 1)
      do_combinations([fixed_card], remaining, count_to_pick)
    end)
  end

  defp do_combinations(stem, remaining, count_to_pick) do
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
