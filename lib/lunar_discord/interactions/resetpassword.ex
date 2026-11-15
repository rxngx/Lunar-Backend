defmodule LunarDiscord.Interactions.ResetPassword do
  @moduledoc """
  Handles /resetpassword slash command — resets a player's password (admin only).
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
      name: "resetpassword",
      description: "[Admin] Reset a player's password",
      options: [
        %{
          type: 3,
          name: "username",
          description: "Username of the player",
          required: true
        },
        %{
          type: 3,
          name: "newpassword",
          description: "New password to set",
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
      new_password = get_option_value(options, "newpassword")

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
        Mongo.update_one(
          Accounts.collection(),
          %{_id: account["_id"]},
          %{"$set" => %{password: new_password}}
        )

        success_embed =
          %Nostrum.Struct.Embed{}
          |> put_title("✅ Mot de passe réinitialisé")
          |> put_description("Le mot de passe de **#{username}** a été mis à jour.")
          |> put_color(0x00CC44)
          |> put_field("Compte", username, true)

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
