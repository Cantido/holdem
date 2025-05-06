defmodule HoldemWeb.GameLive.New do
  use HoldemWeb, :live_view

  alias Holdem.Poker.Game

  def render(assigns) do
    ~H"""
    <.form for={@form}>
      <fieldset class="fieldset bg-base-200 border-base-300 rounded-box w-xs border p-4">
        <legend class="fieldset-legend">New Game</legend>

        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />

        <.inputs_for :let={f_player} field={@form[:players]}>
          <.input
            field={f_player[:name]}
            label="Your name"
            type="text"
            class="input validator"
            required
          />
        </.inputs_for>

        <div class="join">
          <.input
            field={@form[:big_blind]}
            label="Initial bet"
            type="number"
            min="0"
            class="input validator"
            required
          />
          <.input type="select" options={@currencies} label="Currency" name="currency" value="USD" />
        </div>

        <button type="submit" class="btn btn-primary mt-4">Create Game</button>
      </fieldset>
    </.form>
    """
  end

  def mount(_params, _session, socket) do
    form =
      to_form(Game.changeset(%Game{}, %{players: [%{}]}))

    currencies =
      Money.Currency.known_current_currencies()
      |> Enum.map(fn code ->
        {:ok, currency} = Money.Currency.currency_for_code(code)

        {
          Cldr.display_name(currency),
          Atom.to_string(code)
        }
      end)

    socket =
      socket
      |> assign(%{
        form: form,
        currencies: currencies
      })

    {:ok, socket}
  end
end
