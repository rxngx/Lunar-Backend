defmodule LunarWeb.ProfileController do
  use LunarWeb, :controller
  alias Lunar.Mongo
  alias Lunar.DB
  alias Lunar.Database.Tables.{Profiles, Accounts, Items}
  alias Errors
  import Logger

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  # Build the standard MCP profile-command response map.
  defp profile_response(profile, profile_id, base_revision, changes) do
    %{
      "profileRevision" => profile.revision,
      "profileId" => profile_id,
      "profileChangesBaseRevision" => base_revision,
      "profileChanges" => changes,
      "profileCommandRevision" => profile.revision,
      "serverTime" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "responseVersion" => 1
    }
  end

  # Fetch a profile row or return nil.
  defp get_profile(account_id, profile_id) do
    DB.find_profile(account_id, profile_id)
  end

  # Bump revision and persist.
  defp bump_revision(profile) do
    DB.bump_profile_revision(profile)
  end

  # Load all non-stat items for a profile.
  defp load_items(account_id, profile_id) do
    DB.find_items(account_id, profile_id, false)
  end

  # Load all stat items as {key, value} map.
  defp load_stats(account_id, profile_id) do
    DB.find_items(account_id, profile_id, true)
    |> Enum.into(%{}, fn item -> {item[:template_id], format_value(item[:value])} end)
  end

  # Build a full profile-update change (used when client revision is stale).
  defp full_update_change(profile, profile_id, account_id) do
    items =
      load_items(account_id, profile_id)
      |> Enum.reduce(%{}, fn item, acc ->
        item_map = %{
          "attributes" => item.value,
          "templateId" =>
            if String.contains?(item.template_id, "loadout"),
              do: "CosmeticLocker:cosmeticlocker_athena",
              else: item.template_id
        }

        item_map =
          if item.template_id != "Currency:MtxPurchased" do
            if item.quantity != 0, do: Map.put_new(item_map, "quantity", item.quantity), else: item_map
          else
            Map.put_new(item_map, "quantity", item.quantity)
          end

        Map.put(acc, item.template_id, item_map)
      end)

    stats = load_stats(account_id, profile_id)

    %{
      "changeType" => "fullProfileUpdate",
      "profile" => %{
        "profileId" => profile_id,
        "created" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
        "updated" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
        "rvn" => profile.revision,
        "wipeNumber" => 1,
        "accountId" => profile.account_id,
        "version" => "Lunar",
        "items" => items,
        "stats" => %{"attributes" => stats},
        "commandRevision" => profile.revision
      }
    }
  end

  # Resolve the final profileChanges: if client revision is stale send full update.
  defp resolve_changes(profile, profile_id, account_id, query_rvn, changes) do
    base_rvn = String.to_integer(to_string(query_rvn || "-1"))

    if base_rvn != -1 and base_rvn != profile.revision - 1 do
      [full_update_change(profile, profile_id, account_id)]
    else
      changes
    end
  end

  # Find an item by template_id for a given account+profile.
  defp find_item(account_id, profile_id, template_id) do
    DB.find_item(account_id, profile_id, template_id)
  end

  # Upsert a stat value.
  defp upsert_stat(account_id, profile_id, key, value) do
    DB.upsert_stat(account_id, profile_id, key, value)
  end

  # (upsert_stat delegates to DB.upsert_stat above)

  defp format_value(value) do
    case value do
      %{} -> Map.new(value, fn {k, v} -> {k, format_value(v)} end)
      [] -> []
      _ when is_integer(value) or is_float(value) or is_boolean(value) -> value
      _ -> value
    end
  end

  # ---------------------------------------------------------------------------
  # QueryProfile — returns a full profile snapshot
  # ---------------------------------------------------------------------------

  def queryprofile(conn, %{"accountId" => account_id}) do
    profile_id = Map.get(conn.query_params, "profileId")

    profile = get_profile(account_id, profile_id)

    if profile do
      updated_profile = bump_revision(profile)

      items =
        load_items(account_id, profile_id)
        |> Enum.reduce(%{}, fn item, acc ->
          item_map = %{
            "attributes" => item.value,
            "templateId" =>
              if String.contains?(item.template_id, "loadout"),
                do: "CosmeticLocker:cosmeticlocker_athena",
                else: item.template_id
          }

          item_map =
            if item.template_id != "Currency:MtxPurchased" do
              if item.quantity != 0,
                do: Map.put_new(item_map, "quantity", item.quantity),
                else: item_map
            else
              Map.put_new(item_map, "quantity", item.quantity)
            end

          Map.put(acc, item.template_id, item_map)
        end)

      stats = load_stats(account_id, profile_id)

      response = %{
        "profileRevision" => updated_profile.revision,
        "profileId" => profile_id,
        "profileChangesBaseRevision" => updated_profile.revision,
        "profileChanges" => [
          %{
            "changeType" => "fullProfileUpdate",
            "profile" => %{
              "profileId" => profile_id,
              "created" =>
                DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
              "updated" =>
                DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
              "rvn" => updated_profile.revision,
              "wipeNumber" => 1,
              "accountId" => updated_profile.account_id,
              "version" => "Lunar",
              "items" => items,
              "stats" => %{"attributes" => stats},
              "commandRevision" => updated_profile.revision
            }
          }
        ],
        "profileCommandRevision" => updated_profile.revision,
        "serverTime" =>
          DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
        "responseVersion" => 1
      }

      conn |> json(response)
    else
      conn
      |> put_status(:not_found)
      |> json(Errors.mcp() |> Map.get(:template_not_found))
    end
  end

  # ---------------------------------------------------------------------------
  # SetItemFavoriteStatus — toggle favorite on a single item
  # POST /fortnite/api/game/v2/profile/:accountId/client/SetItemFavoriteStatus
  # Body: { targetItemId, bFavorite }
  # ---------------------------------------------------------------------------

  def setitemfavoritestatus(conn, %{"accountId" => account_id}) do
    profile_id = Map.get(conn.query_params, "profileId") || "athena"
    query_rvn = Map.get(conn.query_params, "rvn")
    target_id = Map.get(conn.body_params, "targetItemId")
    b_favorite = Map.get(conn.body_params, "bFavorite", false)

    with profile when not is_nil(profile) <- get_profile(account_id, profile_id),
         item when not is_nil(item) <- find_item(account_id, profile_id, target_id) do
      new_value = Map.put(item.value || %{}, "favorite", b_favorite)
      DB.update_item_fields(item, %{value: new_value})
      updated = bump_revision(profile)

      changes = [
        %{
          "changeType" => "itemAttrChanged",
          "itemId" => target_id,
          "attributeName" => "favorite",
          "attributeValue" => b_favorite
        }
      ]

      final = resolve_changes(updated, profile_id, account_id, query_rvn, changes)
      conn |> json(profile_response(updated, profile_id, profile.revision, final))
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> json(%{"error" => "Item or profile not found"})
    end
  end

  # ---------------------------------------------------------------------------
  # SetItemFavoriteStatusBatch — toggle favorite on multiple items
  # Body: { itemIds: [...], itemFavStatus: [...] }
  # ---------------------------------------------------------------------------

  def setitemfavoritestatusbatch(conn, %{"accountId" => account_id}) do
    profile_id = Map.get(conn.query_params, "profileId") || "athena"
    query_rvn = Map.get(conn.query_params, "rvn")
    item_ids = Map.get(conn.body_params, "itemIds") || []
    fav_statuses = Map.get(conn.body_params, "itemFavStatus") || []

    with profile when not is_nil(profile) <- get_profile(account_id, profile_id) do
      changes =
        item_ids
        |> Enum.with_index()
        |> Enum.flat_map(fn {item_id, idx} ->
          fav = Enum.at(fav_statuses, idx, false)

          case find_item(account_id, profile_id, item_id) do
            nil ->
              []

            item ->
              new_value = Map.put(item.value || %{}, "favorite", fav)
              DB.update_item_fields(item, %{value: new_value})

              [
                %{
                  "changeType" => "itemAttrChanged",
                  "itemId" => item_id,
                  "attributeName" => "favorite",
                  "attributeValue" => fav
                }
              ]
          end
        end)

      updated = bump_revision(profile)
      final = resolve_changes(updated, profile_id, account_id, query_rvn, changes)
      conn |> json(profile_response(updated, profile_id, profile.revision, final))
    else
      _ -> conn |> put_status(:not_found) |> json(%{"error" => "Profile not found"})
    end
  end

  # ---------------------------------------------------------------------------
  # MarkItemSeen — mark one or more items as seen
  # Body: { itemIds: [...] }
  # ---------------------------------------------------------------------------

  def markitemseen(conn, %{"accountId" => account_id}) do
    profile_id = Map.get(conn.query_params, "profileId") || "athena"
    query_rvn = Map.get(conn.query_params, "rvn")
    item_ids = Map.get(conn.body_params, "itemIds") || []

    with profile when not is_nil(profile) <- get_profile(account_id, profile_id) do
      changes =
        item_ids
        |> Enum.flat_map(fn item_id ->
          case find_item(account_id, profile_id, item_id) do
            nil ->
              []

            item ->
              new_value = Map.put(item.value || %{}, "item_seen", true)
              DB.update_item_fields(item, %{value: new_value})

              [
                %{
                  "changeType" => "itemAttrChanged",
                  "itemId" => item_id,
                  "attributeName" => "item_seen",
                  "attributeValue" => true
                }
              ]
          end
        end)

      updated = bump_revision(profile)
      final = resolve_changes(updated, profile_id, account_id, query_rvn, changes)
      conn |> json(profile_response(updated, profile_id, profile.revision, final))
    else
      _ -> conn |> put_status(:not_found) |> json(%{"error" => "Profile not found"})
    end
  end

  # ---------------------------------------------------------------------------
  # SetBattleRoyaleBanner — sets banner_icon and banner_color stats (old locker)
  # Body: { homebaseBannerIconId, homebaseBannerColorId }
  # ---------------------------------------------------------------------------

  def setbattleroyalebanner(conn, %{"accountId" => account_id}) do
    profile_id = Map.get(conn.query_params, "profileId") || "athena"
    query_rvn = Map.get(conn.query_params, "rvn")
    icon = Map.get(conn.body_params, "homebaseBannerIconId")
    color = Map.get(conn.body_params, "homebaseBannerColorId")

    with profile when not is_nil(profile) <- get_profile(account_id, profile_id),
         true <- not is_nil(icon) and not is_nil(color) do
      upsert_stat(account_id, profile_id, "banner_icon", icon)
      upsert_stat(account_id, profile_id, "banner_color", color)
      updated = bump_revision(profile)

      changes = [
        %{"changeType" => "statModified", "name" => "banner_icon", "value" => icon},
        %{"changeType" => "statModified", "name" => "banner_color", "value" => color}
      ]

      final = resolve_changes(updated, profile_id, account_id, query_rvn, changes)
      conn |> json(profile_response(updated, profile_id, profile.revision, final))
    else
      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{"error" => "Missing banner parameters or profile not found"})
    end
  end

  # ---------------------------------------------------------------------------
  # SetCosmeticLockerBanner — sets banner on the locker item itself (new locker)
  # Body: { bannerIconTemplateName, bannerColorTemplateName, lockerItem }
  # ---------------------------------------------------------------------------

  def setcosmeticlockerbanneraction(conn, %{"accountId" => account_id}) do
    profile_id = Map.get(conn.query_params, "profileId") || "athena"
    query_rvn = Map.get(conn.query_params, "rvn")
    icon = Map.get(conn.body_params, "bannerIconTemplateName")
    color = Map.get(conn.body_params, "bannerColorTemplateName")
    locker_item_id = Map.get(conn.body_params, "lockerItem")

    with profile when not is_nil(profile) <- get_profile(account_id, profile_id),
         true <- not is_nil(icon) and not is_nil(color) and not is_nil(locker_item_id),
         item when not is_nil(item) <- find_item(account_id, profile_id, locker_item_id) do
      new_value =
        (item.value || %{})
        |> Map.put("banner_icon_template", icon)
        |> Map.put("banner_color_template", color)

      DB.update_item_fields(item, %{value: new_value})
      updated = bump_revision(profile)

      changes = [
        %{
          "changeType" => "itemAttrChanged",
          "itemId" => locker_item_id,
          "attributeName" => "banner_icon_template",
          "attributeValue" => icon
        },
        %{
          "changeType" => "itemAttrChanged",
          "itemId" => locker_item_id,
          "attributeName" => "banner_color_template",
          "attributeValue" => color
        }
      ]

      final = resolve_changes(updated, profile_id, account_id, query_rvn, changes)
      conn |> json(profile_response(updated, profile_id, profile.revision, final))
    else
      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{"error" => "Missing parameters or item not found"})
    end
  end

  # ---------------------------------------------------------------------------
  # SetCosmeticLockerSlot — equip item in new locker slot + optional variant
  # Body: { category, lockerItem, itemToSlot, slotIndex, variantUpdates }
  # ---------------------------------------------------------------------------

  def setcosmeticlockerslot(conn, %{"accountId" => account_id}) do
    profile_id = Map.get(conn.query_params, "profileId") || "athena"
    query_rvn = Map.get(conn.query_params, "rvn")
    category = Map.get(conn.body_params, "category") || ""
    locker_item_id = Map.get(conn.body_params, "lockerItem") || ""
    item_to_slot = Map.get(conn.body_params, "itemToSlot") || ""
    slot_index = Map.get(conn.body_params, "slotIndex") || 0
    variant_updates = Map.get(conn.body_params, "variantUpdates") || []

    with profile when not is_nil(profile) <- get_profile(account_id, profile_id),
         locker when not is_nil(locker) <- find_item(account_id, profile_id, locker_item_id) do
      locker_data = locker.value || %{}
      changes = []

      # --- Apply variant updates on the item being slotted ---
      {changes, variant_changed} =
        apply_slot_variants(
          account_id,
          profile_id,
          item_to_slot,
          variant_updates,
          locker_data,
          locker_item_id,
          category,
          changes
        )

      # --- Update locker slot ---
      {new_locker_data, slot_changed} =
        update_locker_slot(locker_data, category, item_to_slot, slot_index)

      {updated_locker, changes} =
        if slot_changed or variant_changed do
          new_ld =
            if variant_changed do
              # activeVariants already set inside apply_slot_variants
              new_locker_data
            else
              new_locker_data
            end

          updated = DB.update_item_fields(locker, %{value: new_ld})

          c = [
            %{
              "changeType" => "itemAttrChanged",
              "itemId" => locker_item_id,
              "attributeName" => "locker_slots_data",
              "attributeValue" => new_ld["locker_slots_data"] || new_ld
            }
            | changes
          ]

          {updated, c}
        else
          {locker, changes}
        end

      updated_profile = bump_revision(profile)
      final = resolve_changes(updated_profile, profile_id, account_id, query_rvn, changes)
      conn |> json(profile_response(updated_profile, profile_id, profile.revision, final))
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> json(%{"error" => "Profile or locker item not found"})
    end
  end

  # Apply variantUpdates to both the item itself and the locker slot's activeVariants.
  # Returns {changes, variant_changed}.
  defp apply_slot_variants(
         account_id,
         profile_id,
         item_to_slot,
         variant_updates,
         locker_data,
         locker_item_id,
         category,
         changes
       ) do
    variant_str = Jason.encode!(variant_updates)
    has_active = String.contains?(variant_str, "active")

    if has_active and item_to_slot != "" do
      case find_item(account_id, profile_id, item_to_slot) do
        nil ->
          {changes, false}

        item ->
          existing_variants = get_in(item.value || %{}, ["variants"]) || []

          new_variants =
            Enum.reduce(variant_updates, existing_variants, fn upd, acc ->
              ch = Map.get(upd, "channel", "")

              idx = Enum.find_index(acc, fn v -> Map.get(v, "channel", "") == ch end)

              if idx do
                List.update_at(acc, idx, fn v -> Map.put(v, "active", Map.get(upd, "active", "")) end)
              else
                acc ++ [upd]
              end
            end)

          new_value = Map.put(item.value || %{}, "variants", new_variants)
          DB.update_item_fields(item, %{value: new_value})

          active_variants = [
            %{
              "variants" =>
                Enum.map(variant_updates, fn u ->
                  %{"channel" => Map.get(u, "channel", ""), "active" => Map.get(u, "active", "")}
                end)
            }
          ]

          # Patch locker slot activeVariants inside locker_data
          new_locker_data =
            put_in(
              locker_data,
              ["locker_slots_data", "slots", category, "activeVariants"],
              active_variants
            )

          c = [
            %{
              "changeType" => "itemAttrChanged",
              "itemId" => item_to_slot,
              "attributeName" => "variants",
              "attributeValue" => new_variants
            }
            | changes
          ]

          {c, true}
      end
    else
      {changes, false}
    end
  end

  # Returns {new_locker_data, changed?}
  defp update_locker_slot(locker_data, category, item_to_slot, slot_index) do
    slots_path = ["locker_slots_data", "slots"]

    case category do
      cat
      when cat in [
             "Character",
             "Backpack",
             "Pickaxe",
             "Glider",
             "SkyDiveContrail",
             "MusicPack",
             "LoadingScreen"
           ] ->
        new_data = put_in(locker_data, slots_path ++ [cat, "items"], [item_to_slot])
        {new_data, true}

      "Dance" ->
        idx = max(slot_index, 0)
        current = get_in(locker_data, slots_path ++ ["Dance", "items"]) || List.duplicate("", 6)
        new_items = List.replace_at(current, idx, item_to_slot)
        new_data = put_in(locker_data, slots_path ++ ["Dance", "items"], new_items)
        {new_data, true}

      "ItemWrap" ->
        current = get_in(locker_data, slots_path ++ ["ItemWrap", "items"]) || List.duplicate("", 7)

        new_items =
          cond do
            slot_index < 0 -> List.duplicate(item_to_slot, 7)
            true -> List.replace_at(current, slot_index, item_to_slot)
          end

        new_data = put_in(locker_data, slots_path ++ ["ItemWrap", "items"], new_items)
        {new_data, true}

      _ ->
        {locker_data, false}
    end
  end

  # ---------------------------------------------------------------------------
  # EquipBattleRoyaleCustomization — equip in old-style stats + optional variant
  # Body: { slotName, itemToSlot, indexWithinSlot, variantUpdates }
  # ---------------------------------------------------------------------------

  def equipbattleroyalecustomization(conn, %{"accountId" => account_id}) do
    profile_id = Map.get(conn.query_params, "profileId") || "athena"
    query_rvn = Map.get(conn.query_params, "rvn")
    slot_name = Map.get(conn.body_params, "slotName") || ""
    item_to_slot = Map.get(conn.body_params, "itemToSlot") || ""
    index = Map.get(conn.body_params, "indexWithinSlot") || 0
    variant_updates = Map.get(conn.body_params, "variantUpdates") || []

    with profile when not is_nil(profile) <- get_profile(account_id, profile_id) do
      changes = []

      # --- Variant updates on the item itself ---
      {changes, _variant_changed} =
        if String.contains?(Jason.encode!(variant_updates), "active") and item_to_slot != "" do
          case find_item(account_id, profile_id, item_to_slot) do
            nil ->
              {changes, false}

            item ->
              existing = get_in(item.value || %{}, ["variants"]) || []

              new_variants =
                if existing == [] do
                  variant_updates
                else
                  Enum.reduce(variant_updates, existing, fn upd, acc ->
                    ch = Map.get(upd, "channel", "")
                    idx2 = Enum.find_index(acc, fn v -> Map.get(v, "channel", "") == ch end)

                    if idx2 do
                      List.update_at(acc, idx2, fn v ->
                        Map.put(v, "active", Map.get(upd, "active", ""))
                      end)
                    else
                      acc ++ [upd]
                    end
                  end)
                end

              new_value = Map.put(item.value || %{}, "variants", new_variants)
              DB.update_item_fields(item, %{value: new_value})

              c = [
                %{
                  "changeType" => "itemAttrChanged",
                  "itemId" => item_to_slot,
                  "attributeName" => "variants",
                  "attributeValue" => new_variants
                }
                | changes
              ]

              {c, true}
          end
        else
          {changes, false}
        end

      # --- Update the favorite_* stat ---
      {stat_key, stat_value} = resolve_equip_stat(slot_name, item_to_slot, index, account_id, profile_id)

      changes =
        if stat_key do
          upsert_stat(account_id, profile_id, stat_key, stat_value)
          [%{"changeType" => "statModified", "name" => stat_key, "value" => stat_value} | changes]
        else
          changes
        end

      updated = bump_revision(profile)
      final = resolve_changes(updated, profile_id, account_id, query_rvn, changes)
      conn |> json(profile_response(updated, profile_id, profile.revision, final))
    else
      _ ->
        conn |> put_status(:not_found) |> json(%{"error" => "Profile not found"})
    end
  end

  # Build {stat_key, stat_value} for EquipBattleRoyaleCustomization.
  defp resolve_equip_stat(slot_name, item_to_slot, index, account_id, profile_id) do
    item_key = String.replace(item_to_slot, "item:", "")

    case slot_name do
      s
      when s in [
             "Character",
             "Backpack",
             "Pickaxe",
             "Glider",
             "SkyDiveContrail",
             "MusicPack",
             "LoadingScreen"
           ] ->
        {"favorite_#{String.downcase(s)}", item_key}

      "Dance" ->
        idx = max(index, 0)

        current_dances =
          case find_item(account_id, profile_id, "favorite_dance") do
            nil -> List.duplicate("", 6)
            stat -> stat.value || List.duplicate("", 6)
          end

        new_dances = List.replace_at(current_dances, idx, item_key)
        {"favorite_dance", new_dances}

      "ItemWrap" ->
        new_wraps =
          cond do
            index < 0 -> List.duplicate(item_key, 7)
            true ->
              current =
                case find_item(account_id, profile_id, "favorite_itemwraps") do
                  nil -> List.duplicate("", 7)
                  stat -> stat.value || List.duplicate("", 7)
                end

              List.replace_at(current, index, item_key)
          end

        {"favorite_itemwraps", new_wraps}

      _ ->
        {nil, nil}
    end
  end

  # ---------------------------------------------------------------------------
  # SetVariantAttrs — update variant attributes on an item
  # Body: { itemId, variantUpdates: [{channel, active}] }
  # ---------------------------------------------------------------------------

  def setvariantattrs(conn, %{"accountId" => account_id}) do
    profile_id = Map.get(conn.query_params, "profileId") || "athena"
    query_rvn = Map.get(conn.query_params, "rvn")
    item_id = Map.get(conn.body_params, "itemId") || ""
    variant_updates = Map.get(conn.body_params, "variantUpdates") || []

    with profile when not is_nil(profile) <- get_profile(account_id, profile_id),
         item when not is_nil(item) <- find_item(account_id, profile_id, item_id) do
      existing = get_in(item.value || %{}, ["variants"]) || []

      new_variants =
        Enum.reduce(variant_updates, existing, fn upd, acc ->
          ch = Map.get(upd, "channel", "")
          idx = Enum.find_index(acc, fn v -> Map.get(v, "channel", "") == ch end)

          if idx do
            List.update_at(acc, idx, fn v -> Map.put(v, "active", Map.get(upd, "active", "")) end)
          else
            acc ++ [upd]
          end
        end)

      new_value = Map.put(item.value || %{}, "variants", new_variants)
      DB.update_item_fields(item, %{value: new_value})
      updated = bump_revision(profile)

      changes = [
        %{
          "changeType" => "itemAttrChanged",
          "itemId" => item_id,
          "attributeName" => "variants",
          "attributeValue" => new_variants
        }
      ]

      final = resolve_changes(updated, profile_id, account_id, query_rvn, changes)
      conn |> json(profile_response(updated, profile_id, profile.revision, final))
    else
      _ ->
        conn |> put_status(:not_found) |> json(%{"error" => "Profile or item not found"})
    end
  end

  # ---------------------------------------------------------------------------
  # SetLobbyBackground — sets the active lobby background skin on the profile
  # Body: { backgroundTemplateId }
  # ---------------------------------------------------------------------------

  def setlobbybackground(conn, %{"accountId" => account_id}) do
    profile_id = Map.get(conn.query_params, "profileId") || "athena"
    query_rvn = Map.get(conn.query_params, "rvn")
    bg_id = Map.get(conn.body_params, "backgroundTemplateId") || ""

    with profile when not is_nil(profile) <- get_profile(account_id, profile_id) do
      upsert_stat(account_id, profile_id, "lobby_background", bg_id)
      updated = bump_revision(profile)

      changes = [
        %{
          "changeType" => "statModified",
          "name" => "lobby_background",
          "value" => bg_id
        }
      ]

      final = resolve_changes(updated, profile_id, account_id, query_rvn, changes)
      conn |> json(profile_response(updated, profile_id, profile.revision, final))
    else
      _ -> conn |> put_status(:not_found) |> json(%{"error" => "Profile not found"})
    end
  end

  # ---------------------------------------------------------------------------
  # ClientQuestLogin — grant up to 3 daily quests if the day has rolled over,
  #                    and inject all discovery quests for the current season
  #                    as already-completed so the map/lobby show as discovered.
  #
  # POST /fortnite/api/game/v2/profile/:accountId/client/ClientQuestLogin
  # ---------------------------------------------------------------------------

  @quests_path Path.join(["assets", "athena_quests.json"])

  defp load_quests do
    case File.read(@quests_path) do
      {:ok, raw} -> Jason.decode!(raw)
      _ -> %{}
    end
  end

  # Return today's date as "YYYY-MM-DD" UTC.
  defp today_utc, do: Date.utc_today() |> Date.to_iso8601()

  # Build a UUID-like string (we store quests with the templateId as key
  # since Lunar uses template_id as the item key in the Items table).
  defp make_quest_id, do: "quest-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

  def clientquestlogin(conn, %{"accountId" => account_id}) do
    profile_id = Map.get(conn.query_params, "profileId") || "athena"
    query_rvn  = Map.get(conn.query_params, "rvn")

    with profile when not is_nil(profile) <- get_profile(account_id, profile_id) do
      quests_data = load_quests()
      season      = get_season_from_conn(conn)
      season_pad  = if season < 10, do: "0#{season}", else: "#{season}"
      season_key  = "Season#{season_pad}"

      changes = []

      # ── 1. Daily quests ──────────────────────────────────────────────────
      daily_pool = Map.get(quests_data, "Daily", [])

      {changes, profile} =
        if profile_id == "athena" and daily_pool != [] do
          grant_daily_quests(account_id, profile_id, profile, daily_pool, changes)
        else
          {changes, profile}
        end

      # ── 2. Seasonal quests (ChallengeBundleSchedules + Bundles + Quests) ─
      {changes, profile} =
        if profile_id == "athena" do
          season_data = Map.get(quests_data, season_key, %{})
          inject_seasonal_quests(account_id, profile_id, profile, season_data, season, changes)
        else
          {changes, profile}
        end

      # ── 3. Discovery quests (named locations + landmarks) — Season 11+  ──
      {changes, profile} =
        if profile_id == "athena" and season >= 11 do
          season_data = Map.get(quests_data, season_key, %{})
          inject_discovery_quests(account_id, profile_id, profile, season_data, changes)
        else
          {changes, profile}
        end

      # ── Persist & respond ─────────────────────────────────────────────────
      final = resolve_changes(profile, profile_id, account_id, query_rvn, changes)
      conn  |> json(profile_response(profile, profile_id, profile.revision, final))
    else
      _ -> conn |> put_status(:not_found) |> json(%{"error" => "Profile not found"})
    end
  end

  # Grant up to 3 daily quests if the day has rolled over.
  # Returns {changes, profile} (profile revision bumped only when something changed).
  defp grant_daily_quests(account_id, profile_id, profile, daily_pool, changes) do
    today = today_utc()

    # Read quest_manager stat to check last grant date.
    qm_item   = find_item(account_id, profile_id, "quest_manager")
    qm_value  = (qm_item && qm_item.value) || %{}
    last_date = Map.get(qm_value, "dailyLoginInterval", "") |> String.split("T") |> List.first()
    rerolls   = Map.get(qm_value, "dailyQuestRerolls", 1)

    # Count existing daily quests.
    existing_dailies =
      Mongo.find(Items.collection(), %{
        account_id: account_id,
        profile_id: profile_id,
        is_stat: false,
        template_id: %{"$regex" => "^Quest:AthenaDaily", "$options" => "i"}
      })

    quest_count   = length(existing_dailies)
    should_grant  = last_date != today
    need_count    = max(0, 3 - quest_count)

    if should_grant and need_count > 0 do
      existing_template_ids =
        Enum.map(existing_dailies, & &1.template_id) |> MapSet.new()

      # Pick `need_count` unique quests not already active.
      available = Enum.reject(daily_pool, fn q ->
        MapSet.member?(existing_template_ids, Map.get(q, "templateId", ""))
      end)

      picked = Enum.take(Enum.shuffle(available), need_count)

      {new_changes, _} =
        Enum.reduce(picked, {changes, existing_template_ids}, fn quest, {acc_changes, seen} ->
          template_id = Map.get(quest, "templateId", "")
          objectives  = Map.get(quest, "objectives", [])
          quest_id    = template_id  # use templateId as key so queryprofile maps it cleanly

          attrs =
            %{
              "creation_time"         => DateTime.utc_now() |> DateTime.to_iso8601(),
              "level"                 => -1,
              "item_seen"             => false,
              "sent_new_notification" => false,
              "xp_reward_scalar"      => 1,
              "quest_state"           => "Active",
              "last_state_change_time"=> DateTime.utc_now() |> DateTime.to_iso8601(),
              "max_level_bonus"       => 0,
              "xp"                    => 0,
              "favorite"              => false
            }
            |> Map.merge(
              Enum.into(objectives, %{}, fn obj ->
                {"completion_#{String.downcase(obj)}", 0}
              end)
            )

          DB.insert_item(%{
            account_id: account_id,
            profile_id: profile_id,
            template_id: template_id,
            value: attrs,
            quantity: 1,
            is_stat: false
          })

          new_change = %{
            "changeType" => "itemAdded",
            "itemId"     => quest_id,
            "item"       => %{
              "templateId"  => template_id,
              "attributes"  => attrs,
              "quantity"    => 1
            }
          }

          {[new_change | acc_changes], MapSet.put(seen, template_id)}
        end)

      # Update quest_manager stat (bump rerolls if needed, record today).
      new_rerolls = if rerolls <= 0, do: 1, else: rerolls
      new_qm = qm_value
               |> Map.put("dailyLoginInterval", DateTime.utc_now() |> DateTime.to_iso8601())
               |> Map.put("dailyQuestRerolls", new_rerolls)

      upsert_stat(account_id, profile_id, "quest_manager", new_qm)

      qm_change = %{
        "changeType" => "statModified",
        "name"       => "quest_manager",
        "value"      => new_qm
      }

      updated = bump_revision(profile)
      {[qm_change | new_changes], updated}
    else
      {changes, profile}
    end
  end

  # ---------------------------------------------------------------------------
  # inject_seasonal_quests — grant ChallengeBundleSchedules, ChallengeBundles,
  # and all season quests for the current season (S03–S40+). Idempotent: items
  # already in the DB are skipped. Mirrors LawinServer ClientQuestLogin logic.
  # ---------------------------------------------------------------------------
  defp inject_seasonal_quests(account_id, profile_id, profile, season_data, season, changes) do
    schedules = Map.get(season_data, "ChallengeBundleSchedules", %{})
    bundles   = Map.get(season_data, "ChallengeBundles", %{})
    quests    = Map.get(season_data, "Quests", %{})

    if map_size(schedules) == 0 and map_size(bundles) == 0 do
      {changes, profile}
    else
      # Build set of items already persisted for this profile so we stay idempotent.
      existing_ids =
        Mongo.find(Items.collection(), %{
          account_id: account_id,
          profile_id: profile_id,
          is_stat: false
        })
        |> Enum.map(& &1[:template_id])
        |> MapSet.new()

      now_iso = DateTime.utc_now() |> DateTime.to_iso8601()
      acc_changes = changes

      # ── 1. ChallengeBundleSchedules ───────────────────────────────────────
      acc_changes =
        Enum.reduce(schedules, acc_changes, fn {sched_id, sched}, acc ->
          if MapSet.member?(existing_ids, sched_id) do
            acc
          else
            attrs = %{
              "unlock_epoch"    => now_iso,
              "max_level_bonus" => 0,
              "level"           => 1,
              "item_seen"       => true,
              "xp"              => 0,
              "favorite"        => false,
              "granted_bundles" => Map.get(sched, "granted_bundles", [])
            }

            DB.insert_item(%{
              account_id: account_id,
              profile_id: profile_id,
              template_id: sched_id,
              value: attrs,
              quantity: 1,
              is_stat: false
            })

            [%{
              "changeType" => "itemAdded",
              "itemId"     => sched_id,
              "item"       => %{
                "templateId" => Map.get(sched, "templateId", sched_id),
                "attributes" => attrs,
                "quantity"   => 1
              }
            } | acc]
          end
        end)

      # ── 2. ChallengeBundles ───────────────────────────────────────────────
      # Collect all quest IDs to add from bundles.
      {acc_changes, quests_to_add} =
        Enum.reduce(bundles, {acc_changes, []}, fn {bundle_id, bundle}, {ch_acc, q_acc} ->
          granted   = Map.get(bundle, "grantedquestinstanceids", [])
          # Include questStages if present (S10/S11 prestige)
          granted   = granted ++ Map.get(bundle, "questStages", [])

          attrs = %{
            "has_unlock_by_completion"    => false,
            "num_quests_completed"        => length(granted),
            "level"                       => 0,
            "grantedquestinstanceids"     => granted,
            "item_seen"                   => true,
            "max_allowed_bundle_level"    => 0,
            "num_granted_bundle_quests"   => length(granted),
            "max_level_bonus"             => 0,
            "challenge_bundle_schedule_id"=> Map.get(bundle, "challenge_bundle_schedule_id", ""),
            "num_progress_quests_completed" => length(granted),
            "xp"                          => 0,
            "favorite"                    => false
          }

          # S10/S11 special: bump level for stretch-goal bundles
          attrs =
            if (season == 10 or season == 11) do
              tmpl = String.downcase(Map.get(bundle, "templateId", ""))
              if String.contains?(tmpl, "missionbundle_s10_0") or
                 tmpl == "challengebundle:missionbundle_s11_stretchgoals2" do
                Map.put(attrs, "level", 1)
              else
                attrs
              end
            else
              attrs
            end

          ch_acc2 =
            if MapSet.member?(existing_ids, bundle_id) do
              ch_acc
            else
              DB.insert_item(%{
                account_id: account_id,
                profile_id: profile_id,
                template_id: bundle_id,
                value: attrs,
                quantity: 1,
                is_stat: false
              })

              [%{
                "changeType" => "itemAdded",
                "itemId"     => bundle_id,
                "item"       => %{
                  "templateId" => Map.get(bundle, "templateId", bundle_id),
                  "attributes" => attrs,
                  "quantity"   => 1
                }
              } | ch_acc]
            end

          {ch_acc2, q_acc ++ granted}
        end)

      # ── 3. Individual quests ──────────────────────────────────────────────
      acc_changes =
        Enum.reduce(quests_to_add, acc_changes, fn quest_id, acc ->
          if MapSet.member?(existing_ids, quest_id) do
            acc
          else
            quest = Map.get(quests, quest_id, %{})
            if map_size(quest) == 0 do
              acc
            else
              template_id = Map.get(quest, "templateId", quest_id)
              objectives  = Map.get(quest, "objectives", %{})
              bundle_id   = Map.get(quest, "challenge_bundle_id", "")

              # Set all objectives to their completion target value (Claimed).
              completion_attrs =
                Enum.into(objectives, %{}, fn {k, v} ->
                  {"completion_#{String.downcase(k)}", v}
                end)

              attrs = Map.merge(completion_attrs, %{
                "creation_time"          => now_iso,
                "level"                  => -1,
                "item_seen"              => true,
                "sent_new_notification"  => true,
                "challenge_bundle_id"    => bundle_id,
                "xp_reward_scalar"       => 1,
                "quest_state"            => "Claimed",
                "last_state_change_time" => now_iso,
                "max_level_bonus"        => 0,
                "xp"                     => 0,
                "favorite"               => false
              })

              DB.insert_item(%{
                account_id: account_id,
                profile_id: profile_id,
                template_id: quest_id,
                value: attrs,
                quantity: 1,
                is_stat: false
              })

              [%{
                "changeType" => "itemAdded",
                "itemId"     => quest_id,
                "item"       => %{
                  "templateId" => template_id,
                  "attributes" => attrs,
                  "quantity"   => 1
                }
              } | acc]
            end
          end
        end)

      # Only bump revision when we actually added something.
      if acc_changes == changes do
        {changes, profile}
      else
        updated = bump_revision(profile)
        {acc_changes, updated}
      end
    end
  end

  # Inject all discovery quests (named locations + landmarks) for the season
  # as "Claimed" so the map reveals fully, but only if not already present.
  defp inject_discovery_quests(account_id, profile_id, profile, season_data, changes) do
    bundles = Map.get(season_data, "ChallengeBundles", %{})
    quests  = Map.get(season_data, "Quests", %{})

    # Collect all quest IDs that contain landmark/named-location objectives.
    discovery_quest_ids =
      Enum.flat_map(quests, fn {quest_id, quest} ->
        objectives = Map.get(quest, "objectives", %{})
        is_discovery = Enum.any?(objectives, fn {obj_key, _} ->
          String.contains?(obj_key, "visit_landmark") or
          String.contains?(obj_key, "visit_namedlocation") or
          String.contains?(obj_key, "named_location") or
          String.contains?(obj_key, "visit_named") or
          String.contains?(obj_key, "discover_named")
        end)
        if is_discovery, do: [quest_id], else: []
      end)

    if discovery_quest_ids == [] do
      {changes, profile}
    else
      # Find which are already in the DB.
      existing =
        Mongo.find(Items.collection(), %{
          account_id: account_id,
          profile_id: profile_id,
          is_stat: false,
          template_id: %{"$in" => discovery_quest_ids}
        })
        |> Enum.map(& &1.template_id)
        |> MapSet.new()

      missing = Enum.reject(discovery_quest_ids, &MapSet.member?(existing, &1))

      if missing == [] do
        {changes, profile}
      else
        new_changes =
          Enum.map(missing, fn quest_id ->
            quest = Map.get(quests, quest_id, %{})
            template_id = Map.get(quest, "templateId", quest_id)
            objectives  = Map.get(quest, "objectives", %{})
            bundle_id   = Map.get(quest, "challenge_bundle_id", "")

            # Build completed attributes with all objectives at max value.
            completion_attrs =
              Enum.into(objectives, %{}, fn {k, v} ->
                {"completion_#{String.downcase(k)}", v}
              end)

            attrs = Map.merge(completion_attrs, %{
              "creation_time"         => DateTime.utc_now() |> DateTime.to_iso8601(),
              "level"                 => -1,
              "item_seen"             => true,
              "sent_new_notification" => true,
              "xp_reward_scalar"      => 1,
              "quest_state"           => "Claimed",
              "last_state_change_time"=> DateTime.utc_now() |> DateTime.to_iso8601(),
              "challenge_bundle_id"   => bundle_id,
              "max_level_bonus"       => 0,
              "xp"                    => 0,
              "favorite"              => false
            })

            DB.insert_item(%{
              account_id: account_id,
              profile_id: profile_id,
              template_id: quest_id,
              value: attrs,
              quantity: 1,
              is_stat: false
            })

            %{
              "changeType" => "itemAdded",
              "itemId"     => quest_id,
              "item"       => %{
                "templateId"  => template_id,
                "attributes"  => attrs,
                "quantity"    => 1
              }
            }
          end)

        updated = bump_revision(profile)
        {new_changes ++ changes, updated}
      end
    end
  end

  # Extract season number from User-Agent (reuses Lunar.Version logic).
  defp get_season_from_conn(conn) do
    ua = get_req_header(conn, "user-agent") |> List.first() || ""
    ver = Lunar.Version.get(%{headers: %{"user-agent" => ua}})
    ver.season
  end

  # ---------------------------------------------------------------------------
  # FortRerollDailyQuest — replace one active daily quest with a new random one
  #                        (costs 1 dailyQuestReroll)
  #
  # POST /fortnite/api/game/v2/profile/:accountId/client/FortRerollDailyQuest
  # Body: { questId }
  # ---------------------------------------------------------------------------

  def fortrerolldailyquest(conn, %{"accountId" => account_id}) do
    profile_id  = Map.get(conn.query_params, "profileId") || "athena"
    query_rvn   = Map.get(conn.query_params, "rvn")
    quest_id    = Map.get(conn.body_params, "questId")

    with profile when not is_nil(profile) <- get_profile(account_id, profile_id) do
      quests_data = load_quests()
      daily_pool  = Map.get(quests_data, "Daily", [])

      qm_item  = find_item(account_id, profile_id, "quest_manager")
      qm_value = (qm_item && qm_item.value) || %{}
      rerolls  = Map.get(qm_value, "dailyQuestRerolls", 0)

      if is_nil(quest_id) or rerolls < 1 or daily_pool == [] do
        # Nothing to do — return current profile state unchanged.
        conn |> json(profile_response(profile, profile_id, profile.revision, []))
      else
        # Remove the old quest item.
        old_item = find_item(account_id, profile_id, quest_id)
        if old_item, do: DB.delete_item(old_item)

        # Pick a replacement that isn't already active.
        existing_ids =
          Mongo.find(Items.collection(), %{
            account_id: account_id,
            profile_id: profile_id,
            is_stat: false,
            template_id: %{"$regex" => "^Quest:AthenaDaily", "$options" => "i"}
          })
          |> Enum.map(& &1[:template_id])
          |> MapSet.new()

        available = Enum.reject(daily_pool, fn q ->
          MapSet.member?(existing_ids, Map.get(q, "templateId", ""))
        end)

        new_quest = Enum.random(available)
        template_id = Map.get(new_quest, "templateId")
        objectives  = Map.get(new_quest, "objectives", [])

        attrs =
          %{
            "creation_time"         => DateTime.utc_now() |> DateTime.to_iso8601(),
            "level"                 => -1,
            "item_seen"             => false,
            "sent_new_notification" => false,
            "xp_reward_scalar"      => 1,
            "quest_state"           => "Active",
            "last_state_change_time"=> DateTime.utc_now() |> DateTime.to_iso8601(),
            "max_level_bonus"       => 0,
            "xp"                    => 0,
            "favorite"              => false
          }
          |> Map.merge(
            Enum.into(objectives, %{}, fn obj ->
              {"completion_#{String.downcase(obj)}", 0}
            end)
          )

        DB.insert_item(%{
          account_id: account_id,
          profile_id: profile_id,
          template_id: template_id,
          value: attrs,
          quantity: 1,
          is_stat: false
        })

        # Decrement rerolls.
        new_qm = Map.put(qm_value, "dailyQuestRerolls", rerolls - 1)
        upsert_stat(account_id, profile_id, "quest_manager", new_qm)

        updated = bump_revision(profile)

        changes = [
          %{"changeType" => "statModified",
            "name"       => "quest_manager",
            "value"      => new_qm},
          %{"changeType" => "itemAdded",
            "itemId"     => template_id,
            "item"       => %{"templateId" => template_id, "attributes" => attrs, "quantity" => 1}},
          %{"changeType" => "itemRemoved",
            "itemId"     => quest_id}
        ]

        notifications = [
          %{"type"       => "dailyQuestReroll",
            "primary"    => true,
            "newQuestId" => template_id}
        ]

        final = resolve_changes(updated, profile_id, account_id, query_rvn, changes)

        conn |> json(Map.put(
          profile_response(updated, profile_id, profile.revision, final),
          "notifications", notifications
        ))
      end
    else
      _ -> conn |> put_status(:not_found) |> json(%{"error" => "Profile not found"})
    end
  end

  # ---------------------------------------------------------------------------
  # MarkNewQuestNotificationSent — mark quest notification as delivered
  # Body: { itemIds: [...] }
  # ---------------------------------------------------------------------------

  def marknewquestnotificationsent(conn, %{"accountId" => account_id}) do
    profile_id = Map.get(conn.query_params, "profileId") || "athena"
    query_rvn  = Map.get(conn.query_params, "rvn")
    item_ids   = Map.get(conn.body_params, "itemIds") || []

    with profile when not is_nil(profile) <- get_profile(account_id, profile_id) do
      changes =
        Enum.flat_map(item_ids, fn item_id ->
          case find_item(account_id, profile_id, item_id) do
            nil  -> []
            item ->
              new_value = Map.put(item.value || %{}, "sent_new_notification", true)
              DB.update_item_fields(item, %{value: new_value})
              [%{
                "changeType"     => "itemAttrChanged",
                "itemId"         => item_id,
                "attributeName"  => "sent_new_notification",
                "attributeValue" => true
              }]
          end
        end)

      updated = bump_revision(profile)
      final   = resolve_changes(updated, profile_id, account_id, query_rvn, changes)
      conn    |> json(profile_response(updated, profile_id, profile.revision, final))
    else
      _ -> conn |> put_status(:not_found) |> json(%{"error" => "Profile not found"})
    end
  end

  # ---------------------------------------------------------------------------
  # PurchaseCatalogEntry — buy a BR cosmetic from the item shop
  #
  # POST /fortnite/api/game/v2/profile/:accountId/client/PurchaseCatalogEntry
  # Body: { offerId, purchaseQuantity }
  # profileId query param = "common_core" (V-Bucks are there)
  # Items land in "athena" profile
  # ---------------------------------------------------------------------------

  @catalog_path Path.join(["assets", "catalog.json"])

  defp load_catalog do
    case File.read(@catalog_path) do
      {:ok, raw} -> Jason.decode!(raw)
      _ -> %{"storefronts" => []}
    end
  end

  def purchasecatalogentry(conn, %{"accountId" => account_id}) do
    query_rvn      = Map.get(conn.query_params, "rvn")
    offer_id       = Map.get(conn.body_params, "offerId") || ""
    purchase_qty   = Map.get(conn.body_params, "purchaseQuantity") || 1

    # common_core holds V-Bucks; athena receives the cosmetics.
    cc_profile = get_profile(account_id, "common_core")
    br_profile = get_profile(account_id, "athena")

    if is_nil(cc_profile) or is_nil(br_profile) do
      conn |> put_status(:not_found) |> json(%{"error" => "Profile not found"})
    else
      catalog = load_catalog()

      # Find the matching catalog entry across all BR* storefronts.
      entry = find_catalog_entry(catalog, offer_id)

      if is_nil(entry) do
        conn |> put_status(:bad_request) |> json(%{"error" => "Offer not found"})
      else
        # ── Check if this is a Battle Pass offer ─────────────────────────────
        season = get_season_from_conn(conn)
        bp_data = load_battlepass(season)

        if bp_data && (offer_id == Map.get(bp_data, "battlePassOfferId") or
                       offer_id == Map.get(bp_data, "battleBundleOfferId") or
                       offer_id == Map.get(bp_data, "tierOfferId")) do
          # ── Battle Pass purchase ──────────────────────────────────────────

          # ── Guard: vérifie que le BP n'est pas déjà acheté (sauf achat de tiers) ──
          already_purchased = find_item(account_id, "athena", "book_purchased")
          is_bp_offer = offer_id == Map.get(bp_data, "battlePassOfferId") or
                        offer_id == Map.get(bp_data, "battleBundleOfferId")

          if is_bp_offer && already_purchased && (already_purchased.value == true) &&
             offer_id != Map.get(bp_data, "battleBundleOfferId") do
            conn
            |> put_status(400)
            |> json(%{
              "errorCode"    => "errors.com.epicgames.modules.gamesubcatalog.purchase_not_allowed",
              "errorMessage" => "You already own the Battle Pass for this season.",
              "numericErrorCode" => 1040
            })
          else

          price       = get_in(entry, ["prices", Access.at(0), "finalPrice"]) || 0
          purchase_qty = Map.get(conn.body_params, "purchaseQuantity") || 1
          total_price = price * purchase_qty
          now_iso     = DateTime.utc_now() |> DateTime.to_iso8601()

          # ── Guard: vérifie les fonds suffisants ───────────────────────────
          mtx_check = Mongo.find_one(Items.collection(), %{
            account_id: account_id,
            profile_id: "common_core",
            is_stat: false,
            template_id: %{"$regex" => "^Currency:Mtx", "$options" => "i"}
          })
          current_balance = (mtx_check && mtx_check.quantity) || 0

          if current_balance < total_price do
            conn
            |> put_status(400)
            |> json(%{
              "errorCode"       => "errors.com.epicgames.currency.mtx.insufficient",
              "errorMessage"    => "You cannot afford this item.",
              "numericErrorCode"=> 1040
            })
          else

          # Deduct V-Bucks.
          {cc_changes, _, _} = deduct_vbucks(account_id, total_price)

          # Read current book_level from athena stats.
          book_level_item = find_item(account_id, "athena", "book_level")
          book_level = (book_level_item && book_level_item.value) || 1
          book_level = if is_integer(book_level), do: book_level, else: 1

          # Set book_purchased = true.
          upsert_stat(account_id, "athena", "book_purchased", true)

          ending_tier = book_level

          # Battle bundle = +25 tiers (cap 100).
          if offer_id == Map.get(bp_data, "battleBundleOfferId") do
            new_level = min(book_level + 25, 100)
            upsert_stat(account_id, "athena", "book_level", new_level)
            ending_tier = new_level
          end

          # Grant rewards tier by tier.
          free_rewards  = Map.get(bp_data, "freeRewards", [])
          paid_rewards  = Map.get(bp_data, "paidRewards", [])
          athena_changes = []
          loot_list     = []

          {athena_changes, loot_list} =
            Enum.reduce(0..(ending_tier - 1), {athena_changes, loot_list}, fn tier, {ch_acc, loot_acc} ->
              free_tier = Enum.at(free_rewards, tier) || %{}
              paid_tier = Enum.at(paid_rewards, tier) || %{}

              # Process free rewards.
              {ch_acc, loot_acc} = grant_bp_tier_rewards(free_tier, account_id, "athena", ch_acc, loot_acc, now_iso)
              # Process paid rewards.
              {ch_acc, loot_acc} = grant_bp_tier_rewards(paid_tier, account_id, "athena", ch_acc, loot_acc, now_iso)

              {ch_acc, loot_acc}
            end)

          # Update season_match_boost and season_friend_match_boost stats.
          # (These are accumulated from token rewards in the tiers.)
          updated_br = bump_revision(br_profile)
          updated_cc = bump_revision(cc_profile)

          multi_update = [
            %{
              "profileRevision"            => updated_br.revision,
              "profileId"                  => "athena",
              "profileChangesBaseRevision" => br_profile.revision,
              "profileChanges"             => athena_changes,
              "profileCommandRevision"     => updated_br.revision
            }
          ]

          notification = %{
            "type"       => "CatalogPurchase",
            "primary"    => true,
            "lootResult" => %{"items" => loot_list}
          }

          final_cc = resolve_changes(updated_cc, "common_core", account_id, query_rvn, cc_changes)

          resp = profile_response(updated_cc, "common_core", cc_profile.revision, final_cc)
                 |> Map.put("multiUpdate", multi_update)
                 |> Map.put("notifications", [notification])

          conn |> json(resp)
          end  # insufficient funds check (BP)
          end  # already purchased check (BP)
        else
          # ── Normal cosmetic purchase ────────────────────────────────────────
          price     = get_in(entry, ["prices", Access.at(0), "finalPrice"]) || 0
          grants    = Map.get(entry, "itemGrants") || []

          # ── Guard: vérifie les fonds suffisants ───────────────────────────
          mtx_check_cc = Mongo.find_one(Items.collection(), %{
            account_id: account_id,
            profile_id: "common_core",
            is_stat: false,
            template_id: %{"$regex" => "^Currency:Mtx", "$options" => "i"}
          })
          cc_balance = (mtx_check_cc && mtx_check_cc.quantity) || 0

          if cc_balance < (price * purchase_qty) do
            conn
            |> put_status(400)
            |> json(%{
              "errorCode"       => "errors.com.epicgames.currency.mtx.insufficient",
              "errorMessage"    => "You cannot afford this item.",
              "numericErrorCode"=> 1040
            })
          else

        now_iso   = DateTime.utc_now() |> DateTime.to_iso8601()

        # ── Deduct V-Bucks from common_core ─────────────────────────────────
        {cc_changes, mtx_item_id, new_qty} = deduct_vbucks(account_id, price * purchase_qty)

        # ── Grant cosmetics to athena ────────────────────────────────────────
        {athena_changes, loot_items} =
          Enum.reduce(grants, {[], []}, fn grant, {ch_acc, loot_acc} ->
            template_id = Map.get(grant, "templateId", "")

            # Only add if not already owned.
            already_owned = not is_nil(find_item(account_id, "athena", template_id))

            if already_owned do
              {ch_acc, loot_acc}
            else
              item_id = template_id   # use templateId as stable key

              attrs = %{
                "max_level_bonus" => 0,
                "level"           => 1,
                "item_seen"       => false,
                "xp"              => 0,
                "variants"        => [],
                "favorite"        => false
              }

              DB.insert_item(%{
                account_id: account_id,
                profile_id: "athena",
                template_id: template_id,
                value: attrs,
                quantity: 1,
                is_stat: false
              })

              loot_entry = %{
                "itemType"    => template_id,
                "itemGuid"    => item_id,
                "itemProfile" => "athena",
                "quantity"    => 1
              }

              ch = %{
                "changeType" => "itemAdded",
                "itemId"     => item_id,
                "item"       => %{"templateId" => template_id, "attributes" => attrs, "quantity" => 1}
              }

              {[ch | ch_acc], [loot_entry | loot_acc]}
            end
          end)

        # ── Record in purchase history (enables refund tab) ──────────────────
        purchase_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

        purchase_record = %{
          "purchaseId"       => purchase_id,
          "offerId"          => "v2:/#{purchase_id}",
          "purchaseDate"     => now_iso,
          "freeRefundEligible" => false,
          "fulfillments"     => [],
          "lootResult"       => loot_items,
          "totalMtxPaid"     => price * purchase_qty,
          "metadata"         => %{},
          "gameContext"      => ""
        }

        # Read / update mtx_purchase_history stat on common_core.
        ph_item  = find_item(account_id, "common_core", "mtx_purchase_history")
        ph_value = (ph_item && ph_item.value) || %{
          "refundsUsed"   => 0,
          "refundCredits" => 3,
          "purchases"     => []
        }
        purchases     = Map.get(ph_value, "purchases", [])
        new_ph_value  = Map.put(ph_value, "purchases", purchases ++ [purchase_record])
        upsert_stat(account_id, "common_core", "mtx_purchase_history", new_ph_value)

        ph_change = %{
          "changeType" => "statModified",
          "name"       => "mtx_purchase_history",
          "value"      => new_ph_value
        }

        # ── Bump revisions ───────────────────────────────────────────────────
        updated_cc = bump_revision(cc_profile)
        updated_br = bump_revision(br_profile)

        # common_core profile changes (V-Bucks deduction + purchase history).
        cc_all_changes = [ph_change | cc_changes]

        # athena goes in multiUpdate.
        multi_update = [
          %{
            "profileRevision"            => updated_br.revision,
            "profileId"                  => "athena",
            "profileChangesBaseRevision" => br_profile.revision,
            "profileChanges"             => athena_changes,
            "profileCommandRevision"     => updated_br.revision
          }
        ]

        notification = %{
          "type"       => "CatalogPurchase",
          "primary"    => true,
          "lootResult" => %{"items" => loot_items}
        }

        final_cc = resolve_changes(updated_cc, "common_core", account_id, query_rvn, cc_all_changes)

        resp = Map.put(
          profile_response(updated_cc, "common_core", cc_profile.revision, final_cc),
          "multiUpdate", multi_update
        )
        resp = Map.put(resp, "notifications", [notification])

        conn |> json(resp)
        end  # insufficient funds check (normal purchase)
        end  # Battle Pass vs normal cosmetic
      end    # is_nil(entry) check
    end      # is_nil(cc_profile) check
  end

  # Find the first catalog entry matching offer_id across all storefronts.
  defp find_catalog_entry(catalog, offer_id) do
    storefronts = Map.get(catalog, "storefronts", [])

    Enum.find_value(storefronts, fn sf ->
      entries = Map.get(sf, "catalogEntries", [])
      Enum.find(entries, fn e -> Map.get(e, "offerId") == offer_id end)
    end)
  end

  # Deduct V-Bucks from the first MtxCurrency item in common_core.
  # Returns {changes, item_id, new_quantity}.
  defp deduct_vbucks(account_id, amount) do
    mtx_item =
      Mongo.find_one(Items.collection(), %{
        account_id: account_id,
        profile_id: "common_core",
        is_stat: false,
        template_id: %{"$regex" => "^Currency:Mtx", "$options" => "i"}
      })

    if is_nil(mtx_item) do
      {[], nil, 0}
    else
      new_qty = max(0, (mtx_item.quantity || 0) - amount)
      DB.update_item_fields(mtx_item, %{quantity: new_qty})

      change = %{
        "changeType" => "itemQuantityChanged",
        "itemId"     => mtx_item.template_id,
        "quantity"   => new_qty
      }

      {[change], mtx_item.template_id, new_qty}
    end
  end

  # ---------------------------------------------------------------------------
  # RefundMtxPurchase — refund a cosmetic, restore V-Bucks, remove the item
  #
  # POST /fortnite/api/game/v2/profile/:accountId/client/RefundMtxPurchase
  # Body: { purchaseId }
  # profileId = "common_core"
  # ---------------------------------------------------------------------------

  def refundmtxpurchase(conn, %{"accountId" => account_id}) do
    query_rvn   = Map.get(conn.query_params, "rvn")
    purchase_id = Map.get(conn.body_params, "purchaseId")

    cc_profile = get_profile(account_id, "common_core")
    br_profile = get_profile(account_id, "athena")

    if is_nil(cc_profile) or is_nil(br_profile) or is_nil(purchase_id) do
      conn |> put_status(:bad_request) |> json(%{"error" => "Missing parameters or profile not found"})
    else
      ph_item  = find_item(account_id, "common_core", "mtx_purchase_history")
      ph_value = (ph_item && ph_item.value) || %{"refundsUsed" => 0, "refundCredits" => 3, "purchases" => []}

      purchases      = Map.get(ph_value, "purchases", [])
      refund_credits = Map.get(ph_value, "refundCredits", 0)

      # Find the purchase record.
      target = Enum.find(purchases, fn p -> Map.get(p, "purchaseId") == purchase_id end)

      if is_nil(target) or refund_credits < 1 do
        conn |> put_status(:bad_request) |> json(%{"error" => "Refund not available"})
      else
        total_paid  = Map.get(target, "totalMtxPaid", 0)
        loot_result = Map.get(target, "lootResult", [])
        item_guids  = Enum.map(loot_result, fn l -> Map.get(l, "itemGuid", "") end)

        now_iso = DateTime.utc_now() |> DateTime.to_iso8601()

        # ── Restore V-Bucks ──────────────────────────────────────────────────
        {cc_changes, _item_id, _new_qty} = restore_vbucks(account_id, total_paid)

        # ── Remove cosmetics from athena ─────────────────────────────────────
        athena_changes =
          Enum.flat_map(item_guids, fn item_id ->
            case find_item(account_id, "athena", item_id) do
              nil  -> []
              item ->
                DB.delete_item(item)
                [%{"changeType" => "itemRemoved", "itemId" => item_id}]
            end
          end)

        # ── Update purchase history: stamp refundDate, decrement credit ──────
        updated_purchases =
          Enum.map(purchases, fn p ->
            if Map.get(p, "purchaseId") == purchase_id do
              Map.put(p, "refundDate", now_iso)
            else
              p
            end
          end)

        new_ph_value =
          ph_value
          |> Map.put("refundsUsed",   Map.get(ph_value, "refundsUsed", 0) + 1)
          |> Map.put("refundCredits", refund_credits - 1)
          |> Map.put("purchases",     updated_purchases)

        upsert_stat(account_id, "common_core", "mtx_purchase_history", new_ph_value)

        ph_change = %{
          "changeType" => "statModified",
          "name"       => "mtx_purchase_history",
          "value"      => new_ph_value
        }

        # ── Bump revisions ───────────────────────────────────────────────────
        updated_cc = bump_revision(cc_profile)
        updated_br = bump_revision(br_profile)

        cc_all_changes = [ph_change | cc_changes]

        multi_update = [
          %{
            "profileRevision"            => updated_br.revision,
            "profileId"                  => "athena",
            "profileChangesBaseRevision" => br_profile.revision,
            "profileChanges"             => athena_changes,
            "profileCommandRevision"     => updated_br.revision
          }
        ]

        final_cc = resolve_changes(updated_cc, "common_core", account_id, query_rvn, cc_all_changes)

        resp = Map.put(
          profile_response(updated_cc, "common_core", cc_profile.revision, final_cc),
          "multiUpdate", multi_update
        )

        conn |> json(resp)
      end
    end
  end

  # Restore V-Bucks after a refund.
  defp restore_vbucks(account_id, amount) do
    mtx_item =
      Mongo.find_one(Items.collection(), %{
        account_id: account_id,
        profile_id: "common_core",
        is_stat: false,
        template_id: %{"$regex" => "^Currency:Mtx", "$options" => "i"}
      })

    if is_nil(mtx_item) do
      {[], nil, 0}
    else
      new_qty = (mtx_item.quantity || 0) + amount
      DB.update_item_fields(mtx_item, %{quantity: new_qty})

      change = %{
        "changeType" => "itemQuantityChanged",
        "itemId"     => mtx_item.template_id,
        "quantity"   => new_qty
      }

      {[change], mtx_item.template_id, new_qty}
    end
  end

  # ---------------------------------------------------------------------------
  # UnlockRewardNode — open a Winterfest present (11.31, 19.01, 23.10, 33.11, 39.11)
  #
  # POST /fortnite/api/game/v2/profile/:accountId/client/UnlockRewardNode
  # Body: { nodeId, rewardGraphId }
  # profileId = "athena"
  # ---------------------------------------------------------------------------

  @winterfest_path Path.join(["assets", "winterfest_rewards.json"])

  defp load_winterfest_rewards do
    case File.read(@winterfest_path) do
      {:ok, raw} -> Jason.decode!(raw)
      _ -> %{}
    end
  end

  def unlockrewardnode(conn, %{"accountId" => account_id}) do
    profile_id    = Map.get(conn.query_params, "profileId") || "athena"
    query_rvn     = Map.get(conn.query_params, "rvn")
    node_id       = Map.get(conn.body_params, "nodeId")
    reward_graph_id = Map.get(conn.body_params, "rewardGraphId")

    with profile when not is_nil(profile) <- get_profile(account_id, profile_id),
         true <- not is_nil(node_id) and not is_nil(reward_graph_id) do

      # ── Guard: empêche de réclamer deux fois le même node ────────────────
      graph_check   = find_item(account_id, profile_id, reward_graph_id)
      claimed_nodes = get_in((graph_check && graph_check.value) || %{}, ["reward_nodes_claimed"]) || []

      if node_id in claimed_nodes do
        conn
        |> put_status(400)
        |> json(%{
          "errorCode"    => "errors.com.epicgames.fortnite.reward_already_claimed",
          "errorMessage" => "This reward node has already been claimed."
        })
      else

      rewards_data = load_winterfest_rewards()
      season       = get_season_from_conn(conn)
      season_key   = "Season#{season}"

      season_rewards = Map.get(rewards_data, season_key, %{})
      node_rewards   = Map.get(season_rewards, node_id, [])

      now_iso  = DateTime.utc_now() |> DateTime.to_iso8601()

      # Create the gift box item that shows in the notification.
      gift_id    = "GiftBox-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
      gift_attrs = %{
        "max_level_bonus" => 0,
        "fromAccountId"   => "",
        "lootList"        => [],
        "level"           => 1,
        "item_seen"       => false,
        "xp"              => 0,
        "giftedOn"        => now_iso,
        "params"          => %{"SubGame" => "Athena", "winterfestGift" => "true"},
        "favorite"        => false
      }

      DB.insert_item(%{
        account_id: account_id,
        profile_id: profile_id,
        template_id: gift_id,
        value: gift_attrs,
        quantity: 1,
        is_stat: false
      })

      # Grant each reward — banners go to common_core, everything else to athena.
      {athena_changes, cc_changes, loot_list, cc_modified} =
        Enum.reduce(node_rewards, {[], [], [], false}, fn reward, {ath_ch, cc_ch, loot, cc_mod} ->
          reward_id = "reward-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

          if String.downcase(reward) |> String.starts_with?("homebasebannericon:") do
            # Banner → common_core
            existing = find_item(account_id, "common_core", reward)

            {item_id, cc_change} =
              if existing do
                new_val = Map.put(existing.value || %{}, "item_seen", false)
                DB.update_item_fields(existing, %{value: new_val})
                {existing.template_id, %{"changeType" => "itemAttrChanged",
                   "itemId" => existing.template_id, "attributeName" => "item_seen",
                   "attributeValue" => false}}
              else
                attrs = %{"max_level_bonus" => 0, "level" => 1, "item_seen" => false,
                          "xp" => 0, "variants" => [], "favorite" => false}
                DB.insert_item(%{account_id: account_id, profile_id: "common_core",
                  template_id: reward, value: attrs, quantity: 1, is_stat: false})
                {reward, %{"changeType" => "itemAdded", "itemId" => reward,
                   "item" => %{"templateId" => reward, "attributes" => attrs, "quantity" => 1}}}
              end

            loot_entry = %{"itemType" => reward, "itemGuid" => item_id,
                           "itemProfile" => "common_core",
                           "attributes" => %{"creation_time" => now_iso}, "quantity" => 1}

            {ath_ch, [cc_change | cc_ch], [loot_entry | loot], true}
          else
            # Normal cosmetic → athena
            existing = find_item(account_id, profile_id, reward)

            {item_id, ath_change} =
              if existing do
                new_val = Map.put(existing.value || %{}, "item_seen", false)
                DB.update_item_fields(existing, %{value: new_val})
                {existing.template_id, %{"changeType" => "itemAttrChanged",
                   "itemId" => existing.template_id, "attributeName" => "item_seen",
                   "attributeValue" => false}}
              else
                attrs = %{"max_level_bonus" => 0, "level" => 1, "item_seen" => false,
                          "xp" => 0, "variants" => [], "favorite" => false}
                DB.insert_item(%{account_id: account_id, profile_id: profile_id,
                  template_id: reward, value: attrs, quantity: 1, is_stat: false})
                {reward, %{"changeType" => "itemAdded", "itemId" => reward,
                   "item" => %{"templateId" => reward, "attributes" => attrs, "quantity" => 1}}}
              end

            loot_entry = %{"itemType" => reward, "itemGuid" => item_id,
                           "itemProfile" => "athena",
                           "attributes" => %{"creation_time" => now_iso}, "quantity" => 1}

            {[ath_change | ath_ch], cc_ch, [loot_entry | loot], cc_mod}
          end
        end)

      # Update the gift box lootList with all granted items.
      updated_gift_attrs = Map.put(gift_attrs, "lootList", loot_list)
      gift_item = find_item(account_id, profile_id, gift_id)
      if gift_item, do: DB.update_item_fields(gift_item, %{value: updated_gift_attrs})

      # Update the reward graph item — bump unlock_keys_used, add node to claimed list.
      graph_item = find_item(account_id, profile_id, reward_graph_id)

      {reward_keys_change, nodes_claimed_change} =
        if graph_item do
          graph_val = graph_item.value || %{}
          reward_keys = Map.get(graph_val, "reward_keys", [%{}])
          updated_keys =
            case reward_keys do
              [first | rest] ->
                used = Map.get(first, "unlock_keys_used", 0)
                [Map.put(first, "unlock_keys_used", used + 1) | rest]
              [] -> reward_keys
            end
          claimed = Map.get(graph_val, "reward_nodes_claimed", [])
          new_graph_val =
            graph_val
            |> Map.put("reward_keys", updated_keys)
            |> Map.put("reward_nodes_claimed", [node_id | claimed])
          DB.update_item_fields(graph_item, %{value: new_graph_val})

          rk_ch = %{"changeType" => "itemAttrChanged", "itemId" => reward_graph_id,
                     "attributeName" => "reward_keys", "attributeValue" => updated_keys}
          nc_ch = %{"changeType" => "itemAttrChanged", "itemId" => reward_graph_id,
                     "attributeName" => "reward_nodes_claimed",
                     "attributeValue" => [node_id | claimed]}
          {rk_ch, nc_ch}
        else
          {nil, nil}
        end

      # S11_GIFT_KEY deduction (Season 11 only).
      key_change =
        if season == 11 do
          key_item = find_item(account_id, profile_id, "S11_GIFT_KEY")
          if key_item do
            new_qty = max(0, (key_item.quantity || 1) - 1)
            DB.update_item_fields(key_item, %{quantity: new_qty})
            %{"changeType" => "itemQuantityChanged", "itemId" => "S11_GIFT_KEY", "quantity" => new_qty}
          end
        end

      # Assemble changes.
      gift_box_change = %{"changeType" => "itemAdded", "itemId" => gift_id,
                          "item" => %{"templateId" => "GiftBox:gb_winterfestreward",
                                      "attributes" => updated_gift_attrs, "quantity" => 1}}

      all_athena_changes =
        [gift_box_change | athena_changes]
        ++ [reward_keys_change, nodes_claimed_change, key_change]
        |> Enum.reject(&is_nil/1)

      updated = bump_revision(profile)

      # Build multiUpdate for common_core if banners were granted.
      multi_update =
        if cc_modified do
          cc_profile = get_profile(account_id, "common_core")
          updated_cc = if cc_profile, do: bump_revision(cc_profile), else: cc_profile
          [%{
            "profileRevision"            => (updated_cc && updated_cc.revision) || 0,
            "profileId"                  => "common_core",
            "profileChangesBaseRevision" => (cc_profile && cc_profile.revision) || 0,
            "profileChanges"             => cc_changes,
            "profileCommandRevision"     => (updated_cc && updated_cc.revision) || 0
          }]
        else
          []
        end

      final = resolve_changes(updated, profile_id, account_id, query_rvn, all_athena_changes)

      resp =
        profile_response(updated, profile_id, profile.revision, final)
        |> Map.put("multiUpdate", multi_update)

      conn |> json(resp)
      end  # already_claimed check
    else
      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{"error" => "Missing parameters or profile not found"})
    end
  end

  # ---------------------------------------------------------------------------
  # RemoveGiftBox — dismiss the gift box popup after opening a present
  #
  # POST /fortnite/api/game/v2/profile/:accountId/client/RemoveGiftBox
  # Body: { giftBoxItemId } (11.31)  OR  { giftBoxItemIds: [...] } (19.01+)
  # ---------------------------------------------------------------------------

  def removegiftbox(conn, %{"accountId" => account_id}) do
    profile_id  = Map.get(conn.query_params, "profileId") || "athena"
    query_rvn   = Map.get(conn.query_params, "rvn")
    single_id   = Map.get(conn.body_params, "giftBoxItemId")
    multi_ids   = Map.get(conn.body_params, "giftBoxItemIds") || []

    ids_to_remove =
      (if single_id, do: [single_id], else: []) ++ multi_ids

    with profile when not is_nil(profile) <- get_profile(account_id, profile_id) do
      changes =
        Enum.flat_map(ids_to_remove, fn item_id ->
          case find_item(account_id, profile_id, item_id) do
            nil  -> []
            item ->
              DB.delete_item(item)
              [%{"changeType" => "itemRemoved", "itemId" => item_id}]
          end
        end)

      updated = bump_revision(profile)
      final   = resolve_changes(updated, profile_id, account_id, query_rvn, changes)
      conn    |> json(profile_response(updated, profile_id, profile.revision, final))
    else
      _ -> conn |> put_status(:not_found) |> json(%{"error" => "Profile not found"})
    end
  end

  # ---------------------------------------------------------------------------
  # GiftCatalogEntry — gift an item shop offer to friends
  #
  # POST /fortnite/api/game/v2/profile/:accountId/client/GiftCatalogEntry
  # Body: { offerId, receiverAccountIds, giftWrapTemplateId, personalMessage }
  # profileId = "common_core"
  # ---------------------------------------------------------------------------

  def giftcatalogentry(conn, %{"accountId" => account_id}) do
    query_rvn     = Map.get(conn.query_params, "rvn")
    offer_id      = Map.get(conn.body_params, "offerId") || ""
    receiver_ids  = Map.get(conn.body_params, "receiverAccountIds") || []
    gift_wrap     = Map.get(conn.body_params, "giftWrapTemplateId") || "GiftBox:gb_default"
    message       = Map.get(conn.body_params, "personalMessage") || ""

    valid_gift_boxes = ["GiftBox:gb_default", "GiftBox:gb_giftwrap1",
                        "GiftBox:gb_giftwrap2", "GiftBox:gb_giftwrap3"]

    cc_profile = get_profile(account_id, "common_core")

    cond do
      is_nil(cc_profile) ->
        conn |> put_status(:not_found) |> json(%{"error" => "Profile not found"})

      not (gift_wrap in valid_gift_boxes) ->
        conn |> put_status(400) |> json(%{"error" => "Invalid gift box template."})

      length(receiver_ids) < 1 or length(receiver_ids) > 5 ->
        conn |> put_status(400) |> json(%{"error" => "Must specify 1-5 receivers."})

      String.length(message) > 100 ->
        conn |> put_status(400) |> json(%{"error" => "Personal message too long."})

      true ->
        catalog = load_catalog()
        entry = find_catalog_entry(catalog, offer_id)

        if is_nil(entry) do
          conn |> put_status(400) |> json(%{"error" => "Offer not found"})
        else
          price  = get_in(entry, ["prices", Access.at(0), "finalPrice"]) || 0
          grants = Map.get(entry, "itemGrants") || []
          now_iso = DateTime.utc_now() |> DateTime.to_iso8601()

          # Deduct V-Bucks from sender (once per gift, not per receiver).
          {cc_changes, _, _} = deduct_vbucks(account_id, price)

          all_changes = cc_changes
          notifications = []

          # Process each receiver.
          multi_update =
            Enum.flat_map(receiver_ids, fn receiver_id ->
              br_profile = get_profile(receiver_id, "athena")

              if is_nil(br_profile) do
                []
              else
                br_changes =
                  Enum.flat_map(grants, fn grant ->
                  template_id = Map.get(grant, "templateId", "")

                  # Skip if receiver already owns it.
                  unless is_nil(find_item(receiver_id, "athena", template_id)) do
                    []
                  else
                    item_id = template_id
                    attrs = %{
                      "max_level_bonus" => 0,
                      "level"           => 1,
                      "item_seen"       => false,
                      "xp"              => 0,
                      "variants"        => [],
                      "favorite"        => false
                    }

                    DB.insert_item(%{
                      account_id: receiver_id,
                      profile_id: "athena",
                      template_id: template_id,
                      value: attrs,
                      quantity: 1,
                      is_stat: false
                    })

                    [
                      %{
                        "changeType" => "itemAdded",
                        "itemId"     => item_id,
                        "item"       => %{"templateId" => template_id,
                                          "attributes" => attrs, "quantity" => 1}
                      }
                    ]
                  end
                end)

              if br_changes == [] do
                []
              else
                # Create gift box in receiver's common_core.
                gift_id = "gift-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
                loot_list =
                  Enum.map(grants, fn g ->
                    %{"itemType" => Map.get(g, "templateId", ""),
                      "itemGuid" => Map.get(g, "templateId", ""),
                      "itemProfile" => "athena", "quantity" => 1}
                  end)

                gift_attrs = %{
                  "fromAccountId" => account_id,
                  "lootList"      => loot_list,
                  "params"        => %{"userMessage" => message},
                  "level"         => 1,
                  "giftedOn"      => now_iso
                }

                DB.insert_item(%{
                  account_id: receiver_id,
                  profile_id: "common_core",
                  template_id: gift_id,
                  value: gift_attrs,
                  quantity: 1,
                  is_stat: false
                })

                receiver_br = get_profile(receiver_id, "athena")
                updated_br = if receiver_br, do: bump_revision(receiver_br)

                [
                  %{
                    "profileRevision"            => (updated_br && updated_br.revision) || 0,
                    "profileId"                  => "athena",
                    "profileChangesBaseRevision" => (receiver_br && receiver_br.revision) || 0,
                    "profileChanges"             => br_changes,
                    "profileCommandRevision"     => (updated_br && updated_br.revision) || 0
                  }
                ]
              end
              end  # is_nil(br_profile) check
            end)

          updated_cc = bump_revision(cc_profile)
          final = resolve_changes(updated_cc, "common_core", account_id, query_rvn, all_changes)

          conn |> json(profile_response(updated_cc, "common_core", cc_profile.revision, final)
                       |> Map.put("multiUpdate", multi_update)
                       |> Map.put("notifications", notifications))
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Battle Pass helpers
  # ---------------------------------------------------------------------------

  @battlepass_dir Path.join(["assets", "battlepass"])

  defp load_battlepass(season) do
    file = Path.join(@battlepass_dir, "Season#{season}.json")
    case File.read(file) do
      {:ok, raw} -> Jason.decode!(raw)
      _ -> nil
    end
  end

  # Grant rewards from a single Battle Pass tier.
  # Returns {changes, loot_list}.
  defp grant_bp_tier_rewards(tier_rewards, account_id, profile_id, ch_acc, loot_acc, now_iso) do
    Enum.reduce(tier_rewards, {ch_acc, loot_acc}, fn {item, qty}, {ch, loot} ->
      item_lower = String.downcase(item)

      cond do
        # XP boost tokens → update stats, don't add as items.
        item_lower == "token:athenaseasonxpboost" ->
          boost_item = find_item(account_id, profile_id, "season_match_boost")
          current = (boost_item && boost_item.value) || 0
          new_val = current + qty
          upsert_stat(account_id, profile_id, "season_match_boost", new_val)
          {[%{"changeType" => "statModified", "name" => "season_match_boost",
              "value" => new_val} | ch], loot}

        item_lower == "token:athenaseasonfriendxpboost" ->
          boost_item = find_item(account_id, profile_id, "season_friend_match_boost")
          current = (boost_item && boost_item.value) || 0
          new_val = current + qty
          upsert_stat(account_id, profile_id, "season_friend_match_boost", new_val)
          {[%{"changeType" => "statModified", "name" => "season_friend_match_boost",
              "value" => new_val} | ch], loot}

        # Currency → add V-Bucks.
        String.starts_with?(item_lower, "currency:mtx") ->
          {cc_changes, _, _} = restore_vbucks(account_id, qty)
          {cc_changes ++ ch, loot}

        # Athena cosmetics → add to athena.
        String.starts_with?(item_lower, "athena") or
        String.starts_with?(item_lower, "homebasebanner") ->
          existing = find_item(account_id, profile_id, item)

          if existing do
            # Mark as unseen.
            new_val = Map.put(existing.value || %{}, "item_seen", false)
            DB.update_item_fields(existing, %{value: new_val})
            {[%{"changeType" => "itemAttrChanged", "itemId" => item,
                "attributeName" => "item_seen", "attributeValue" => false} | ch], loot}
          else
            attrs = %{
              "max_level_bonus" => 0,
              "level"           => 1,
              "item_seen"       => false,
              "xp"              => 0,
              "variants"        => [],
              "favorite"        => false
            }

            DB.insert_item(%{
              account_id: account_id,
              profile_id: profile_id,
              template_id: item,
              value: attrs,
              quantity: qty,
              is_stat: false
            })

            loot_entry = %{"itemType" => item, "itemGuid" => item,
                           "quantity" => qty}
            {[%{"changeType" => "itemAdded", "itemId" => item,
                "item" => %{"templateId" => item, "attributes" => attrs,
                            "quantity" => qty}} | ch],
             [loot_entry | loot]}
          end

        # Account resources (XP etc) → add to athena as items.
        String.starts_with?(item_lower, "accountresource:") ->
          existing = find_item(account_id, profile_id, item)
          if existing do
            new_qty = (existing.quantity || 0) + qty
            DB.update_item_fields(existing, %{quantity: new_qty})
            {[%{"changeType" => "itemQuantityChanged", "itemId" => item,
                "quantity" => new_qty} | ch], loot}
          else
            DB.insert_item(%{
              account_id: account_id,
              profile_id: profile_id,
              template_id: item,
              value: %{},
              quantity: qty,
              is_stat: false
            })
            {[%{"changeType" => "itemAdded", "itemId" => item,
                "item" => %{"templateId" => item, "attributes" => %{},
                            "quantity" => qty}} | ch], loot}
          end

        true ->
          {ch, loot}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers shared by format_value (unchanged)
  # ---------------------------------------------------------------------------

  defp profile_update(profile, changes) do
    %{
      "profileRevision" => profile.revision + 1,
      "profileId" => profile.type,
      "profileChangesBaseRevision" => profile.revision,
      "profileChanges" => changes,
      "profileCommandRevision" => profile.revision || 0,
      "serverTime" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "responseVersion" => 1
    }
  end
end
