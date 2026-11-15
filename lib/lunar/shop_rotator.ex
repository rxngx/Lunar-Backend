defmodule Lunar.ShopRotator do
  @moduledoc """
  GenServer that rotates the item shop daily at midnight UTC.
  Fetches cosmetics from fortnite-api.com and writes assets/catalog.json
  (preserving other storefronts such as the Battle Pass).
  Can be configured in config/runtime.exs.
  """
  use GenServer
  require Logger

  @catalog_path Path.join(["assets", "catalog.json"])
  @fortnite_api_url "https://fortnite-api.com/v2/cosmetics/br"

  # Rarity → price tables (ported from Reload-Backend autorotate.js)
  @prices %{
    "outfit" => %{"legendary" => 2000, "epic" => 1500, "rare" => 1200, "uncommon" => 800},
    "emote"  => %{"legendary" => 2000, "epic" => 800,  "rare" => 500,  "uncommon" => 200},
    "spray"  => %{"legendary" => 2000, "epic" => 800,  "rare" => 500,  "uncommon" => 200},
    "emoji"  => %{"legendary" => 2000, "epic" => 800,  "rare" => 500,  "uncommon" => 200},
    "backpack"      => %{"legendary" => 2000, "epic" => 1500, "rare" => 1200, "uncommon" => 200},
    "glider"        => %{"legendary" => 2000, "epic" => 1200, "rare" => 800,  "uncommon" => 500},
    "pickaxe"       => %{"epic" => 1200, "rare" => 800, "uncommon" => 500},
    "wrap"          => %{"legendary" => 1200, "epic" => 700, "rare" => 500,   "uncommon" => 300},
    "loadingscreen" => %{"legendary" => 500, "epic" => 500, "rare" => 500, "uncommon" => 200},
    "music"         => %{"legendary" => 500, "epic" => 500, "rare" => 200, "uncommon" => 200}
  }

  @series_prices %{
    "gaming legends series" => %{"outfit" => 1500, "pickaxe" => 1200, "backpack" => 1200,
                                  "emote" => 500, "glider" => 1200, "wrap" => 700,
                                  "loadingscreen" => 500, "music" => 200, "emoji" => 200},
    "marvel series" => %{"outfit" => 1500},
    "star wars series" => %{"outfit" => 1500},
    "dc series" => %{"outfit" => 1500},
    "icon series" => %{"outfit" => 1500, "pickaxe" => 1200, "backpack" => 1200,
                       "emote" => 500, "glider" => 1200, "wrap" => 700,
                       "loadingscreen" => 500, "music" => 200, "emoji" => 200},
    "lava series" => %{"outfit" => 2000, "glider" => 2000, "backpack" => 2000,
                       "pickaxe" => 1200, "loadingscreen" => 500, "music" => 200, "emoji" => 200}
  }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    enabled = Application.get_env(:lunar, :shop_auto_rotate, false)

    if enabled do
      schedule_rotation()
      Logger.info("[ShopRotator] Auto-rotation enabled — first rotation scheduled.")
    else
      Logger.info("[ShopRotator] Auto-rotation disabled.")
    end

    {:ok, %{enabled: enabled}}
  end

  @impl true
  def handle_info(:rotate, state) do
    if state.enabled do
      Logger.info("[ShopRotator] Rotating item shop...")
      rotate()
      schedule_rotation()
    end

    {:noreply, state}
  end

  # Public trigger for manual rotation.
  def rotate_now, do: GenServer.cast(__MODULE__, :rotate_now)

  @impl true
  def handle_cast(:rotate_now, state) do
    rotate()
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Schedule the next rotation at the next midnight UTC.
  # ---------------------------------------------------------------------------
  defp schedule_rotation do
    ms = ms_until_midnight_utc()
    Logger.info("[ShopRotator] Next rotation in #{div(ms, 60_000)} minutes.")
    Process.send_after(self(), :rotate, ms)
  end

  defp ms_until_midnight_utc do
    now = DateTime.utc_now()
    midnight =
      %DateTime{now | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
      |> DateTime.add(86_400, :second)
    max(DateTime.diff(midnight, now, :millisecond), 1_000)
  end

  # ---------------------------------------------------------------------------
  # Main rotation logic — fetch, pick, write config.
  # ---------------------------------------------------------------------------
  def rotate do
    daily_count    = Application.get_env(:lunar, :shop_daily_count, 6)
    featured_count = Application.get_env(:lunar, :shop_featured_count, 2)
    chapter_limit  = Application.get_env(:lunar, :shop_chapter_limit, 1)
    season_limit   = Application.get_env(:lunar, :shop_season_limit, "10")

    case fetch_cosmetics(chapter_limit, season_limit) do
      {:ok, cosmetics} ->
        daily    = pick_items(cosmetics, daily_count)
        featured = pick_items(cosmetics, featured_count)

        # Read existing catalog to preserve BP and other storefronts.
        existing_catalog =
          case File.read(@catalog_path) do
            {:ok, raw} -> Jason.decode!(raw)
            _          -> %{"storefronts" => []}
          end

        daily_entries    = build_catalog_entries(daily)
        featured_entries = build_catalog_entries(featured)

        storefronts =
          existing_catalog
          |> Map.get("storefronts", [])
          |> upsert_storefront("BRDailyStorefront", daily_entries)
          |> upsert_storefront("BRWeeklyStorefront", featured_entries)

        new_catalog = Map.put(existing_catalog, "storefronts", storefronts)
        File.write!(@catalog_path, Jason.encode!(new_catalog, pretty: true))
        Logger.info("[ShopRotator] Shop rotated — #{length(daily)} daily, #{length(featured)} featured items.")

      {:error, reason} ->
        Logger.error("[ShopRotator] Failed to fetch cosmetics: #{inspect(reason)}")
    end
  end

  # Insert or replace a named storefront in the list.
  defp upsert_storefront(storefronts, name, entries) do
    sf = %{"name" => name, "catalogEntries" => entries}
    case Enum.find_index(storefronts, fn s -> Map.get(s, "name") == name end) do
      nil -> storefronts ++ [sf]
      idx -> List.replace_at(storefronts, idx, sf)
    end
  end

  defp fetch_cosmetics(chapter_limit, season_limit) do
    excluded = Application.get_env(:lunar, :shop_excluded_items, [])

    case :httpc.request(:get, {String.to_charlist(@fortnite_api_url), []}, [], []) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        body_str = to_string(body)
        case Jason.decode(body_str) do
          {:ok, %{"data" => items}} ->
            filtered = Enum.filter(items, fn item ->
              id       = Map.get(item, "id", "")
              rarity   = get_in(item, ["rarity", "displayValue"]) |> to_string() |> String.downcase()
              chapter  = get_in(item, ["introduction", "chapter"]) |> to_string() |> Integer.parse() |> elem_or(0)
              season   = get_in(item, ["introduction", "season"]) |> to_string()
              type     = get_in(item, ["type", "value"]) |> to_string() |> String.downcase()

              not (id in excluded) and
              rarity != "common" and
              chapter >= 1 and
              chapter <= chapter_limit and
              type in ["outfit", "emote", "backpack", "glider", "pickaxe",
                       "loadingscreen", "emoji", "wrap", "spray", "music"] and
              season_ok?(chapter, chapter_limit, season, season_limit)
            end)

            {:ok, filtered}

          {:error, e} -> {:error, e}
        end

      {:error, e} -> {:error, e}
    end
  end

  defp elem_or({n, _}, _), do: n
  defp elem_or(:error, default), do: default

  defp season_ok?(chapter, chapter_limit, _season, _limit) when chapter < chapter_limit, do: true
  defp season_ok?(chapter, chapter_limit, season, limit) when chapter == chapter_limit do
    cond do
      limit == "OG" -> true
      season == "X" -> false
      true ->
        case {Integer.parse(season), Integer.parse(limit)} do
          {{s, _}, {l, _}} -> s <= l
          _ -> false
        end
    end
  end
  defp season_ok?(_, _, _, _), do: false

  # ---------------------------------------------------------------------------
  # Pick items spread across types — mirrors autorotate.js pickRandomItems.
  # ---------------------------------------------------------------------------
  defp pick_items(cosmetics, count) do
    buckets = Enum.group_by(cosmetics, fn item ->
      get_in(item, ["type", "value"]) |> to_string() |> String.downcase()
    end)

    picks_by_type = [{"outfit", 2}, {"emote", 1}, {"backpack", 1},
                     {"glider", 1}, {"pickaxe", 1}, {"loadingscreen", 1}, {"emoji", 1}]

    selected =
      Enum.flat_map(picks_by_type, fn {type, n} ->
        bucket = Map.get(buckets, type, [])
        bucket |> Enum.shuffle() |> Enum.take(n)
      end)

    # Fill remaining slots from any type.
    remaining = count - length(selected)

    leftovers =
      cosmetics
      |> Enum.reject(fn i -> Enum.member?(selected, i) end)
      |> Enum.shuffle()
      |> Enum.take(max(remaining, 0))

    Enum.take(selected ++ leftovers, count)
  end

  # ---------------------------------------------------------------------------
  # Build proper Fortnite catalog entries from picked items.
  # ---------------------------------------------------------------------------
  defp build_catalog_entries(items) do
    Enum.with_index(items, 1)
    |> Enum.map(fn {item, idx} ->
      template_id = item_to_template_id(item)
      price       = item_price(item)
      offer_id    = "v2:/autorotate_#{idx}_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"

      %{
        "offerId"              => offer_id,
        "offerType"            => "StaticPrice",
        "devName"              => template_id,
        "itemGrants"           => [%{"templateId" => template_id, "quantity" => 1}],
        "prices"               => [%{
          "currencyType"    => "MtxCurrency",
          "currencySubType" => "MtxPurchaseBonus",
          "regularPrice"    => price,
          "finalPrice"      => price,
          "saleExpiration"  => "9999-12-31T23:59:59.999Z",
          "basePrice"       => price
        }],
        "requirements"         => [],
        "metaInfo"             => [],
        "catalogGroupPriority" => 0,
        "sortPriority"         => idx,
        "title"                => "",
        "shortDescription"     => "",
        "description"          => "",
        "displayAssetPath"     => "",
        "newDisplayAssetPath"  => ""
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Build catalog_config entries from picked items (kept for compatibility).
  # ---------------------------------------------------------------------------
  defp build_config(items, prefix) do
    items
    |> Enum.with_index(1)
    |> Enum.map(fn {item, idx} ->
      key         = "#{prefix}#{idx}"
      template_id = item_to_template_id(item)
      price       = item_price(item)

      {key, %{
        "itemGrants" => [template_id],
        "price"      => price,
        "displayAssetPath" => "",
        "NewDisplayAssetPath" => ""
      }}
    end)
  end

  defp item_to_template_id(item) do
    id   = Map.get(item, "id", "")
    type = get_in(item, ["type", "value"]) |> to_string() |> String.downcase()
    backend = get_in(item, ["type", "backendValue"]) |> to_string()

    prefix =
      case type do
        "outfit"        -> "AthenaCharacter"
        "emote"         -> "AthenaDance"
        "backpack"      -> "AthenaBackpack"
        "glider"        -> "AthenaGlider"
        "pickaxe"       -> "AthenaPickaxe"
        "loadingscreen" -> "AthenaLoadingScreen"
        "wrap"          -> "AthenaItemWrap"
        "spray"         -> "AthenaDance"
        "emoji"         -> "AthenaDance"
        "music"         -> "AthenaMusicPack"
        _ -> backend || "Athena#{String.capitalize(type)}"
      end

    "#{prefix}:#{id}"
  end

  defp item_price(item) do
    rarity = get_in(item, ["rarity", "displayValue"]) |> to_string() |> String.downcase()
    type   = get_in(item, ["type", "value"]) |> to_string() |> String.downcase()
    series = get_in(item, ["series", "value"]) |> to_string() |> String.downcase()

    cond do
      series != "" ->
        series_map = Map.get(@series_prices, series, %{})
        Map.get(series_map, type) || 999

      true ->
        type_map = Map.get(@prices, type, %{})
        Map.get(type_map, rarity) || 999
    end
  end
end
