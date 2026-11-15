defmodule LunarWeb.PageController do
  use LunarWeb, :controller

  def home(conn, _params) do
    conn
    |> put_status(200)
    |> text("Welcome to Lunar!")
  end
end
