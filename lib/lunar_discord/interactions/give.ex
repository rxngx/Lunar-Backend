defmodule LunarDiscord.Interactions.Give do
  @moduledoc """
  Handles /give slash command — grants V-Bucks to a player (admin only).
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
      name: "give",
      description: "[Admin] Give V-Bucks to a player",
      options: [
        %{
          type: 3,
          name: "username",
          description: "Username of the player",
          required: true
        },
        %{
          type: 4,
          name: "amount",
          description: "Number of V-Bucks to give",
          required: true
        }
      ]
    }

  @impl Behaviour
  @spec handle_interaction(Interaction.t(), Behaviour.interaction_options()) :: map()
  def handle_interaction(interaction, options) do
    caller_id = to_string(interaction.user.id)
    admin_ids = Application.get_env(:lunar, :admin_discord_ids, [])

    if caller_id not in Enum.map(admin_ids, &to_string/1) do
      error_embed =
        %Nostrum.Struct.Embed{}
        |> put_title("❌ Permission refusée")
        |> put_description("Cette commande est réservée aux administrateurs.")
        |> put_color(0xFF0000)

      %{
        type: InteractionCallbackType.channel_message_with_source(),
        data: %{embeds: [error_embed], flags: 64}
      }
    else
      username = get_option_value(options, "username")
      amount = get_option_value(options, "amount")

      with {:ok, amount_int} <- parse_amount(amount),
           account when not is_nil(account) <-
             Mongo.find_one(Accounts.collection(), %{username: username}) do
        account_id = account["account_id"]

        item =
          Mongo.find_one(Items.collection(), %{
            account_id: account_id,
            profile_id: "common_core",
            template_id: %{"$regex" => "^Currency:MtxPurchased"}
          })

        new_qty =
          if item do
            current_qty = Map.get(item, "quantity", 0)
            qty = current_qty + amount_int

            Mongo.update_one(
              Items.collection(),
              %{_id: item["_id"]},
              %{"$set" => %{quantity: qty}}
            )

            qty
          else
            Mongo.insert_one(Items.collection(), %{
              account_id: account_id,
              profile_id: "common_core",
              template_id: "Currency:MtxPurchased",
              value: %{platform: "EpicPC"},
              quantity: amount_int,
              is_stat: false
            })

            amount_int
          end

        # Bump common_core revision
        Mongo.update_one(
          Lunar.Database.Tables.Profiles.collection(),
          %{account_id: account_id, profile_id: "common_core"},
          %{"$inc" => %{revision: 1}}
        )

        success_embed =
          %Nostrum.Struct.Embed{}
          |> put_title("✅ V-Bucks accordés")
          |> put_description("Les V-Bucks ont été ajoutés avec succès.")
          |> put_color(0x00C3FF)
          |> put_field("Joueur", username, true)
          |> put_field("Montant ajouté", "#{amount_int} V-Bucks", true)
          |> put_field("Nouveau solde", "#{new_qty} V-Bucks", true)

        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{embeds: [success_embed], flags: 64}
        }
      else
        nil ->
          not_found_embed =
            %Nostrum.Struct.Embed{}
            |> put_title("❌ Joueur introuvable")
            |> put_description("Aucun compte trouvé pour l'utilisateur **#{username}**.")
            |> put_color(0xFF4444)

          %{
            type: InteractionCallbackType.channel_message_with_source(),
            data: %{embeds: [not_found_embed], flags: 64}
          }

        {:error, reason} ->
          err_embed =
            %Nostrum.Struct.Embed{}
            |> put_title("❌ Erreur")
            |> put_description(reason)
            |> put_color(0xFF4444)

          %{
            type: InteractionCallbackType.channel_message_with_source(),
            data: %{embeds: [err_embed], flags: 64}
          }
      end
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp get_option_value(nil, _name), do: nil

  defp get_option_value(options, name) do
    case Enum.find(options, fn opt -> opt.name == name end) do
      nil -> nil
      opt -> opt.value
    end
  end

  defp parse_amount(nil), do: {:error, "Montant manquant."}
  defp parse_amount(amount) when is_integer(amount) and amount > 0, do: {:ok, amount}
  defp parse_amount(amount) when is_integer(amount), do: {:error, "Le montant doit être supérieur à 0."}

  defp parse_amount(amount) when is_binary(amount) do
    case Integer.parse(amount) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, "Montant invalide : #{amount}"}
    end
  end

  defp parse_amount(_), do: {:error, "Montant invalide."}
end
