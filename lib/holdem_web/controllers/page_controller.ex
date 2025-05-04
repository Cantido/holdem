defmodule HoldemWeb.PageController do
  use HoldemWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
