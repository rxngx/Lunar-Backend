defmodule LunarWeb.ApiController do
  use LunarWeb, :controller
  alias Lunar.Mongo
  alias Lunar.Database.Tables.{Accounts, Items, Profiles}

  @vbucks_rewards %{"Kill" => 25, "Win" => 50, "Assist" => 5, "Match" => 10}
  @api_key "lunar-api-key"

  def grant_vbucks(conn, params) do
    apikey   = Map.get(params, "apikey")
    username = Map.get(params, "username")
    reason   = Map.get(params, "reason")

    cond do
      is_nil(apikey) or apikey != @api_key ->
        conn |> put_status(401) |> json(%{"code" => "401", "error" => "Invalid or missing API key."})

      is_nil(username) ->
        conn |> put_status(400) |> json(%{"code" => "400", "error" => "Missing username."})

      is_nil(reason) ->
        conn |> put_status(400) |> json(%{"code" => "400", "error" => "Missing reason."})

      true ->
        add_value = Map.get(@vbucks_rewards, reason)

        if is_nil(add_value) do
          conn |> put_status(400) |> json(%{
            "code" => "400",
            "error" => "Invalid reason. Allowed values: #{Enum.join(Map.keys(@vbucks_rewards), ", ")}."
          })
        else
          api_username = String.trim(username) |> String.downcase()

          # Find account by username (case-insensitive via regex).
          account =
            Mongo.find_one(Accounts.collection(), %{
              username: %{"$regex" => "^#{Regex.escape(api_username)}$", "$options" => "i"}
            })

          if is_nil(account) do
            conn |> put_status(200) |> json(%{"message" => "User not found."})
          else
            grant_vbucks_to_account(account[:account_id], add_value, reason)
            conn |> put_status(200) |> json(%{
              "message" => "V-Bucks granted successfully.",
              "username" => account[:username],
              "reason" => reason,
              "amount" => add_value
            })
          end
        end
    end
  end

  defp grant_vbucks_to_account(account_id, amount, _reason) do
    now_iso = DateTime.utc_now() |> DateTime.to_iso8601()

    # Find MtxPurchased in common_core.
    mtx_item =
      Mongo.find_one(Items.collection(), %{
        account_id: account_id,
        profile_id: "common_core",
        is_stat: false,
        template_id: %{"$regex" => "^Currency:Mtx", "$options" => "i"}
      })

    if mtx_item do
      new_qty = (mtx_item[:quantity] || 0) + amount
      Mongo.update_one(Items.collection(), %{_id: mtx_item[:_id]},
        %{"$set" => %{quantity: new_qty}})

      # Also bump profile0 if it has a MtxPurchased entry.
      profile0_mtx =
        Mongo.find_one(Items.collection(), %{
          account_id: account_id,
          profile_id: "profile0",
          is_stat: false,
          template_id: %{"$regex" => "^Currency:Mtx", "$options" => "i"}
        })

      if profile0_mtx do
        p0_qty = (profile0_mtx[:quantity] || 0) + amount
        Mongo.update_one(Items.collection(), %{_id: profile0_mtx[:_id]},
          %{"$set" => %{quantity: p0_qty}})
      end

      # Create gift box entry.
      gift_id = "gift-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
      Mongo.insert_one(Items.collection(), %{
        account_id: account_id,
        profile_id: "common_core",
        template_id: gift_id,
        value: %{
          "fromAccountId" => "[Administrator]",
          "lootList" => [%{"itemType" => "Currency:MtxGiveaway",
                           "itemGuid" => "Currency:MtxGiveaway",
                           "quantity" => amount}],
          "params" => %{"userMessage" => "V-Bucks earned in-game!"},
          "giftedOn" => now_iso
        },
        quantity: 1,
        is_stat: false
      })

      # Bump common_core profile revision.
      case Mongo.find_one(Profiles.collection(), %{account_id: account_id, type: "common_core"}) do
        nil -> :ok
        profile ->
          Mongo.update_one(Profiles.collection(), %{_id: profile[:_id]},
            %{"$set" => %{revision: (profile[:revision] || 0) + 1}})
      end
    end
  end
end
