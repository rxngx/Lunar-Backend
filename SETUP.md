# Lunar — Setup Guide

## 1. Install Erlang & Elixir

**Erlang**
Download and install from [erlang.org/downloads](https://www.erlang.org/downloads).
Make sure to add Erlang to your system PATH during installation.

**Elixir**
Once Erlang is installed, grab Elixir from [elixir-lang.org/install](https://elixir-lang.org/install.html).
Pick the version that matches your Erlang install.

---

## 2. Install MongoDB

Lunar uses **MongoDB** as its database — no PostgreSQL needed.

1. Download MongoDB Community Edition from [mongodb.com/try/download/community](https://www.mongodb.com/try/download/community).
2. Run the installer and follow the steps for your OS.
3. Start the MongoDB service:
   - **Windows:** MongoDB runs as a service automatically after install.
   - **macOS/Linux:** `mongod --config /usr/local/etc/mongod.conf`
4. *(Optional)* Install [MongoDB Compass](https://www.mongodb.com/products/compass) for a visual database interface.

By default Lunar connects to `mongodb://localhost:27017/lunar_dev`. You can change this in `config/dev.exs`.

---

## 3. Configure Lunar

**`config/dev.exs`** — MongoDB URL and Discord bot token:

```elixir
# MongoDB
config :lunar, Lunar.Mongo,
  url: "mongodb://localhost:27017/lunar_dev"

# Discord bot (Nostrum)
config :nostrum, :token, "your_discord_bot_token_here"
```

Replace `"your_discord_bot_token_here"` with the token from your [Discord Developer Portal](https://discord.com/developers/applications) bot page.

---

## 4. Install Dependencies

```bash
mix deps.get
```

---

## 5. Start the Server

```bash
mix phx.server
```

Lunar is now running. MongoDB collections and indexes are created automatically on first start — no migration commands needed.

---

## Troubleshooting

- **MongoDB not connecting** — make sure the MongoDB service is running and the URL in `config/dev.exs` is correct.
- **Discord bot not responding** — double-check your Nostrum token.
- **Port conflict** — Lunar defaults to port `4000`. Change it in `config/dev.exs` if needed.
