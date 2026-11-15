defmodule LunarWeb.MatchmakingController do
  use LunarWeb, :controller

  def findplayer(conn, _params) do
    conn
    |> put_status(204)
    |> json([])
  end
end
