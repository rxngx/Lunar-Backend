defmodule LunarWeb.AccountController do
  use LunarWeb, :controller
  alias Lunar.Mongo
  alias Errors
  alias Lunar.Database.Tables.{Accounts}

  def public(conn, %{"accountId" => account_id}) do
    case Mongo.find_one(Accounts.collection(), %{account_id: account_id}) do
      nil ->
        error_details = Errors.account() |> Map.get(:account_not_found)
        conn |> put_status(:not_found) |> json(error_details)

      account ->
        conn |> put_status(200) |> json(%{
          id: account[:account_id],
          displayName: account[:username],
          externalAuths: %{}
        })
    end
  end

  def public2(conn, _params) do
    conn |> put_status(200) |> json(%{})
  end

  def externalauths(conn, %{"accountId" => account_id}) do
    conn |> put_status(200) |> json([])
  end

  def ssodomains(conn, _params) do
    conn |> put_status(200) |> json([
      "fortnite.com",
      "unrealengine.com",
      "epicgames.com"
    ])
  end
end
