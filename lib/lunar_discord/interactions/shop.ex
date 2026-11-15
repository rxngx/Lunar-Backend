defmodule LunarDiscord.Interactions.Shop do
  @moduledoc """
  Handles /shop slash command — previews the current Item Shop.
  """

  import Nostrum.Struct.Embed
  alias Nostrum.Constants.InteractionCallbackType
  alias Nostrum.Struct.{ApplicationCommand, Interaction}
  alias LunarDiscord.Behaviour

  @behaviour Behaviour

  @catalog_path "assets/catalog.json"

  @impl LunarDiscord.Behaviour
  @spec get_command() :: ApplicationCommand.application_command_map()
  def get_command,
    do: %{
      name: "shop",
      description: "Preview the current Lunar Item Shop"
    }

  @impl Behaviour
  @spec handle_interaction(Interaction.t(), Behaviour.interaction_options()) :: map()
  def handle_interaction(_interaction, _options) do
    case read_catalog() do
      {:ok, catalog} ->
        entries = extract_daily_entries(catalog)

        embed =
          %Nostrum.Struct.Embed{}
          |> put_title("🛒 Item Shop du jour")
          |> put_color(0x9B59B6)
          |> put_description(build_shop_description(entries))

        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{embeds: [embed], flags: 64}
        }

      {:error, reason} ->
        err_embed =
          %Nostrum.Struct.Embed{}
          |> put_title("❌ Shop indisponible")
          |> put_description("Impossible de lire le shop : #{reason}")
          |> put_color(0xFF4444)

        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{embeds: [err_embed], flags: 64}
        }
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp read_catalog do
    path = Path.join(File.cwd!(), @catalog_path)

    with {:ok, raw} <- File.read(path),
         {:ok, json} <- Jason.decode(raw) do
      {:ok, json}
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp extract_daily_entries(catalog) do
    storefronts = Map.get(catalog, "storefronts", [])

    daily =
      Enum.find(storefronts, fn sf ->
        Map.get(sf, "name", "") == "BRDailyStorefront"
      end)

    if daily do
      daily
      |> Map.get("catalogEntries", [])
      |> Enum.take(10)
    else
      []
    end
  end

  defp build_shop_description([]) do
    "_Le shop est vide ou indisponible pour le moment._"
  end

  defp build_shop_description(entries) do
    entries
    |> Enum.map(fn entry ->
      name = extract_display_name(entry)
      price = extract_price(entry)
      "• **#{name}** — #{price} V-Bucks"
    end)
    |> Enum.join("\n")
  end

  defp extract_display_name(entry) do
    grants = Map.get(entry, "itemGrants", [])

    case grants do
      [%{"templateId" => tid} | _] ->
        tid
        |> String.split(":")
        |> List.last()
        |> String.replace("_", " ")

      _ ->
        Map.get(entry, "offerId", "Unknown")
    end
  end

  defp extract_price(entry) do
    prices = Map.get(entry, "prices", [])

    case prices do
      [%{"finalPrice" => p} | _] -> p
      [%{"regularPrice" => p} | _] -> p
      _ -> "?"
    end
  end
end
