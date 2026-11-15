defmodule LunarDiscord.Consumer do
  @moduledoc """
  Consumes events from the Discord API connection
  """

  require Logger
  use Nostrum.Consumer

  def handle_event({:READY, _data, _ws_state}) do
    LunarDiscord.Interactions.register_commands()

    Nostrum.Api.update_status(:online, "Lunar")

    Logger.info("Lunar Discord service started!")
  end

  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    LunarDiscord.Interactions.handle_interaction(interaction)
  end

  def handle_event({_event, _data, _ws}) do
    :noop
  end
end
