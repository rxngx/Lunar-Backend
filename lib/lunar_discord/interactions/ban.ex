defmodule LunarDiscord.Interactions.Ban do
  @moduledoc """
  Handles /ban slash command — ban or unban a player (admin only).
  """

  import Nostrum.Struct.Embed
  alias Nostrum.Constants.InteractionCallbackType
  alias Nostrum.Struct.{ApplicationCommand, Interaction}
  alias Lunar.Database.Tables.Accounts
  alias Lunar.Mongo
  alias LunarDiscord.Behaviour

  @behaviour Behaviour

  @impl LunarDiscord.Behaviour
  @spec get_command() :: ApplicationCommand.application_command_map()
  def get_command,
    do: %{
      name: "ban",
      description: "[Admin] Ban or unban a player",
      options: [
        %{
          type: 3,
          name: "username",
          description: "Username of the player",
          required: true
        },
        %{
          type: 3,
          name: "action",
          description: "ban or unban",
          required: true,
          choices: [
            %{name: "Ban", value: "ban"},
            %{name: "Unban", value: "unban"}
          ]
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
      action = get_option_value(options, "action")

      account = Mongo.find_one(Accounts.collection(), %{username: username})

      if is_nil(account) do
        not_found_embed =
          %Nostrum.Struct.Embed{}
          |> put_title("❌ Joueur introuvable")
          |> put_description("Aucun compte trouvé pour **#{username}**.")
          |> put_color(0xFF4444)

        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{embeds: [not_found_embed], flags: 64}
        }
      else
        banned = action == "ban"

        Mongo.update_one(
          Accounts.collection(),
          %{_id: account["_id"]},
          %{"$set" => %{banned: banned}}
        )

        {title, color, verb} =
          if banned do
            {"🔨 Joueur banni", 0xFF4444, "banni"}
          else
            {"✅ Joueur débanni", 0x00CC44, "débanni"}
          end

        success_embed =
          %Nostrum.Struct.Embed{}
          |> put_title(title)
          |> put_description("Le joueur **#{username}** a été #{verb} avec succès.")
          |> put_color(color)
          |> put_field("Compte", username, true)
          |> put_field("Action", String.upcase(action), true)

        %{
          type: InteractionCallbackType.channel_message_with_source(),
          data: %{embeds: [success_embed], flags: 64}
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
end
