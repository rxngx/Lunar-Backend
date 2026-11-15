defmodule LunarDiscord.Interactions.Stats do
  @moduledoc """
  Handles /stats slash command — shows account stats for the calling Discord user.
  """

  import Nostrum.Struct.Embed
  alias Nostrum.Constants.InteractionCallbackType
  alias Nostrum.Struct.{ApplicationCommand, Interaction}
  alias Lunar.Database.Tables.{Accounts, Items}
  alias Lunar.Mongo
  alias LunarDiscord.Behaviour

  @behaviour Behaviour

  @impl LunarDiscord.Behaviour
  @spec get_command() :: ApplicationCommand.application_command_map()
  def get_command,
    do: %{
      name: "stats",
      description: "View your Lunar account stats"
    }

  @impl Behaviour
  @spec handle_interaction(Interaction.t(), Behaviour.interaction_options()) :: map()
  def handle_interaction(interaction, _options) do
    discord_id = to_string(interaction.user.id)

    account = Mongo.find_one(Accounts.collection(), %{discord_id: discord_id})

    if is_nil(account) do
      not_linked_embed =
        %Nostrum.Struct.Embed{}
        |> put_title("❌ Aucun compte lié")
        |> put_description("Tu n'as pas encore de compte Lunar. Utilise `/register` pour en créer un.")
        |> put_color(0xFF4444)

      %{
        type: InteractionCallbackType.channel_message_with_source(),
        data: %{embeds: [not_linked_embed], flags: 64}
      }
    else
      account_id = account["account_id"]
      username = account["username"]

      # Fetch V-Bucks
      vbucks_item =
        Mongo.find_one(Items.collection(), %{
          account_id: account_id,
          profile_id: "common_core",
          template_id: %{"$regex" => "^Currency:MtxPurchased"}
        })

      vbucks = if vbucks_item, do: Map.get(vbucks_item, "quantity", 0), else: 0

      # Fetch BR stats items
      all_stats =
        Items.collection()
        |> Mongo.find(%{account_id: account_id, profile_id: "athena", is_stat: true})
        |> Enum.to_list()

      level = find_stat_value(all_stats, "s11_level", "Level")
      wins = find_stat_value(all_stats, "lifetime_wins", "LifetimeWins")
      book_level = find_stat_value(all_stats, "book_level", "BookLevel")
      book_purchased = find_stat_bool(all_stats, "book_purchased", "BookPurchased")

      stats_embed =
        %Nostrum.Struct.Embed{}
        |> put_title("📊 Statistiques de #{username}")
        |> put_color(0x00C3FF)
        |> put_field("👤 Pseudo", username, true)
        |> put_field("💰 V-Bucks", "#{vbucks}", true)
        |> put_field("⭐ Niveau", "#{level}", true)
        |> put_field("🏆 Victoires", "#{wins}", true)
        |> put_field("📖 Niveau Battle Pass", "#{book_level}", true)
        |> put_field("🎟️ Battle Pass acheté", if(book_purchased, do: "✅ Oui", else: "❌ Non"), true)

      %{
        type: InteractionCallbackType.channel_message_with_source(),
        data: %{embeds: [stats_embed], flags: 64}
      }
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp find_stat_value(stats, template_suffix, _fallback_key) do
    item = Enum.find(stats, fn i ->
      tid = Map.get(i, "template_id", "")
      String.contains?(tid, template_suffix)
    end)

    if item, do: Map.get(item, "quantity", 0), else: 0
  end

  defp find_stat_bool(stats, template_suffix, _fallback_key) do
    item = Enum.find(stats, fn i ->
      tid = Map.get(i, "template_id", "")
      String.contains?(tid, template_suffix)
    end)

    if item, do: Map.get(item, "value", false) == true, else: false
  end
end
