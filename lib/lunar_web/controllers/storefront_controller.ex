defmodule LunarWeb.StorefrontController do
  use LunarWeb, :controller

  def keychain(conn, _params) do
    file_path = Path.join(["assets", "keychain.json"])

    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, json} ->
            conn
            |> put_status(200)
            |> json(json)

          {:error, _} ->
            conn
            |> put_status(500)
            |> json(%{error: "Failed to decode JSON"})
        end

      {:error, _} ->
        conn
        |> put_status(500)
        |> json(%{error: "Failed to read file"})
    end
  end


  def receipts(conn, %{"accountId" => _account_id}) do 
    conn
    |> put_status(200)
    |> json([])
  end

  def offers(conn, %{"accountId" => _account_id}) do 
    conn
    |> put_status(200)
    |> json([])
  end
  
def catalog(conn, _params) do
    file_path = Path.join(["assets", "catalog.json"])

    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, json} ->
            conn
            |> put_status(200)
            |> json(json)

          {:error, _} ->
            conn
            |> put_status(500)
            |> json(%{error: "Failed to decode JSON"})
        end

      {:error, _} ->
        conn
        |> put_status(500)
        |> json(%{error: "Failed to read file"})
    end
  end

  # ---------------------------------------------------------------------------
  # Gift eligibility check — verifies the receiver is friends with the sender
  # and doesn't already own the offered items.
  # GET /fortnite/api/storefront/v2/gift/check_eligibility/recipient/:recipientId/offer/:offerId
  # ---------------------------------------------------------------------------
  def gift_eligibility(conn, %{"recipientId" => recipient_id, "offerId" => offer_id}) do
    sender_id = conn |> get_req_header("x-epic-account-id") |> List.first() || ""

    catalog = load_catalog_for_gift()
    entry = find_offer(catalog, offer_id)

    if is_nil(entry) do
      conn |> put_status(400) |> json(%{"error" => "Offer not found"})
    else
      # Check friendship (unless gifting self).
      if sender_id != recipient_id do
        friend = Lunar.Mongo.find_one(Lunar.Database.Tables.Friends.collection(),
          %{account_id: sender_id, friend_id: recipient_id, status: "accepted"})

        if is_nil(friend) do
          conn |> put_status(403) |> json(%{
            "errorCode" => "errors.com.epicgames.friends.no_relationship",
            "errorMessage" => "You are not friends with this player."
          })
        end
      end

      # Check if receiver already owns any of the granted items.
      grants = Map.get(entry, "itemGrants") || []

      already_owned =
        Enum.any?(grants, fn g ->
          template_id = Map.get(g, "templateId", "")
          not is_nil(Lunar.Mongo.find_one(Lunar.Database.Tables.Items.collection(),
            %{account_id: recipient_id, profile_id: "athena", template_id: template_id}))
        end)

      if already_owned do
        conn |> put_status(403) |> json(%{
          "errorCode" => "errors.com.epicgames.modules.gamesubcatalog.purchase_not_allowed",
          "errorMessage" => "Receiver already owns one or more items."
        })
      else
        conn |> json(%{
          "price" => get_in(entry, ["prices", Access.at(0)]) || %{},
          "items" => grants
        })
      end
    end
  end

  defp load_catalog_for_gift do
    case File.read(Path.join(["assets", "catalog.json"])) do
      {:ok, raw} -> Jason.decode!(raw)
      _ -> %{"storefronts" => []}
    end
  end

  defp find_offer(catalog, offer_id) do
    storefronts = Map.get(catalog, "storefronts", [])
    Enum.find_value(storefronts, fn sf ->
      Enum.find(Map.get(sf, "catalogEntries", []), fn e ->
        Map.get(e, "offerId") == offer_id
      end)
    end)
  end
end
