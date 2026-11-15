defmodule LunarWeb.FriendsController do
  use LunarWeb, :controller
  alias Lunar.Mongo
  alias Lunar.Database.Tables.{Friends, Accounts}

  defp get_friends(account_id) do
    Mongo.find(Friends.collection(), %{account_id: account_id})
  end

  defp get_friend_row(account_id, friend_id) do
    Mongo.find_one(Friends.collection(), %{account_id: account_id, friend_id: friend_id})
  end

  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp upsert_friend(account_id, friend_id, status) do
    case get_friend_row(account_id, friend_id) do
      nil ->
        Mongo.insert_one(Friends.collection(), %{
          account_id: account_id,
          friend_id: friend_id,
          status: status,
          alias: "",
          created: now_iso()
        })
      existing ->
        Mongo.update_one(Friends.collection(),
          %{_id: existing[:_id]},
          %{"$set" => %{status: status}})
    end
  end

  defp delete_friend_row(account_id, friend_id) do
    case get_friend_row(account_id, friend_id) do
      nil -> :ok
      row -> Mongo.delete_one(Friends.collection(), %{_id: row[:_id]})
    end
  end

  def settings(conn, _params), do: conn |> json(%{})

  def blocklist(conn, %{"accountId" => account_id}) do
    blocked =
      Mongo.find(Friends.collection(), %{account_id: account_id, status: "blocked"})
      |> Enum.map(& &1[:friend_id])

    conn |> json(%{"blockedUsers" => blocked})
  end

  def recent_players(conn, _params), do: conn |> json([])

  def public_friends(conn, %{"accountId" => account_id}) do
    friends = get_friends(account_id)

    response =
      Enum.flat_map(friends, fn f ->
        case f[:status] do
          "accepted" ->
            [%{"accountId" => f[:friend_id], "status" => "ACCEPTED",
               "direction" => "OUTBOUND", "created" => f[:created], "favorite" => false}]
          "incoming" ->
            [%{"accountId" => f[:friend_id], "status" => "PENDING",
               "direction" => "INBOUND", "created" => f[:created], "favorite" => false}]
          "outgoing" ->
            [%{"accountId" => f[:friend_id], "status" => "PENDING",
               "direction" => "OUTBOUND", "created" => f[:created], "favorite" => false}]
          _ -> []
        end
      end)

    conn |> json(response)
  end

  def send_or_accept(conn, %{"receiverId" => receiver_id}) do
    sender_id = conn |> get_req_header("x-epic-account-id") |> List.first() ||
                 Map.get(conn.query_params, "accountId", "")

    if sender_id == "" do
      conn |> put_status(403) |> json(%{"error" => "No account context"})
    else
      sender_row = get_friend_row(sender_id, receiver_id)

      cond do
        sender_row && sender_row[:status] == "incoming" ->
          upsert_friend(sender_id, receiver_id, "accepted")
          upsert_friend(receiver_id, sender_id, "accepted")

        is_nil(sender_row) or sender_row[:status] != "outgoing" ->
          upsert_friend(sender_id, receiver_id, "outgoing")
          upsert_friend(receiver_id, sender_id, "incoming")

        true -> :ok
      end

      conn |> put_status(204) |> text("")
    end
  end

  def delete_friend(conn, %{"receiverId" => receiver_id}) do
    sender_id = conn |> get_req_header("x-epic-account-id") |> List.first() ||
               Map.get(conn.query_params, "accountId", "")

    if sender_id != "" do
      delete_friend_row(sender_id, receiver_id)
      delete_friend_row(receiver_id, sender_id)
    end

    conn |> put_status(204) |> text("")
  end

  def block_friend(conn, %{"receiverId" => receiver_id}) do
    sender_id = conn |> get_req_header("x-epic-account-id") |> List.first() ||
               Map.get(conn.query_params, "accountId", "")

    if sender_id != "" do
      upsert_friend(sender_id, receiver_id, "blocked")
      delete_friend_row(receiver_id, sender_id)
    end

    conn |> put_status(204) |> text("")
  end

  def unblock_friend(conn, %{"receiverId" => receiver_id}) do
    sender_id = conn |> get_req_header("x-epic-account-id") |> List.first() ||
               Map.get(conn.query_params, "accountId", "")

    if sender_id != "" do
      delete_friend_row(sender_id, receiver_id)
    end

    conn |> put_status(204) |> text("")
  end

  def summary(conn, %{"accountId" => account_id}) do
    friends = get_friends(account_id)

    {accepted, incoming, outgoing, blocked} =
      Enum.reduce(friends, {[], [], [], []}, fn f, {a, i, o, b} ->
        case f[:status] do
          "accepted" ->
            {[%{"accountId" => f[:friend_id], "groups" => [], "mutual" => 0,
                "alias" => f[:alias] || "", "note" => "", "favorite" => false,
                "created" => f[:created]} | a], i, o, b}
          "incoming" ->
            {a, [%{"accountId" => f[:friend_id], "mutual" => 0,
                   "favorite" => false, "created" => f[:created]} | i], o, b}
          "outgoing" ->
            {a, i, [%{"accountId" => f[:friend_id], "favorite" => false} | o], b}
          "blocked" ->
            {a, i, o, [%{"accountId" => f[:friend_id]} | b]}
          _ -> {a, i, o, b}
        end
      end)

    conn |> json(%{
      "friends" => Enum.reverse(accepted),
      "incoming" => Enum.reverse(incoming),
      "outgoing" => Enum.reverse(outgoing),
      "suggested" => [],
      "blocklist" => Enum.reverse(blocked),
      "settings" => %{"acceptInvites" => "public"}
    })
  end

  def friend_alias(conn, %{"friendId" => friend_id}) do
    account_id = conn |> get_req_header("x-epic-account-id") |> List.first() ||
                 Map.get(conn.query_params, "accountId", "")

    row = get_friend_row(account_id, friend_id)

    if row && row[:status] == "accepted" do
      case conn.method do
        "PUT" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn, length: 100)
          alias_str = String.slice(body, 0, 16)
          Mongo.update_one(Friends.collection(), %{_id: row[:_id]},
            %{"$set" => %{alias: alias_str}})

        "DELETE" ->
          Mongo.update_one(Friends.collection(), %{_id: row[:_id]},
            %{"$set" => %{alias: ""}})
      end

      conn |> put_status(204) |> text("")
    else
      conn |> put_status(404) |> json(%{"error" => "Friendship not found"})
    end
  end

  def enabled(conn, _params), do: conn |> put_status(200) |> json([])
  def empty(conn, _params), do: conn |> put_status(200) |> json(%{})
end
