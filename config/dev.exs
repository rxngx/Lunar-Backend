import Config

# Configure MongoDB for development
config :lunar, Lunar.Mongo,
  url: "mongodb://localhost:27017/lunar_dev"

# Discord Bot (Nostrum)
# Replace with your Discord bot token from https://discord.com/developers/applications
config :nostrum,
  token: System.get_env("DISCORD_BOT_TOKEN") || "your_discord_bot_token_here",
  gateway_intents: :all

# Discord user IDs permitted to run admin commands (/give, /ban, /resetpassword)
# You can put your Discord numeric user ID here (e.g. ["123456789012345678"])
config :lunar, :admin_discord_ids,
  System.get_env("DISCORD_ADMIN_IDS", "")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)
