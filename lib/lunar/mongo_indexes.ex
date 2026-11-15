defmodule Lunar.MongoIndexes do
  @moduledoc """
  Creates MongoDB indexes at startup. Run this once after Mongo starts.
  Called from the application start, via a Task.
  """
  require Logger

  def create_all do
    Task.start(fn ->
      :timer.sleep(2_000)  # Wait for Mongo to be ready
      create_indexes()
      Logger.info("[MongoIndexes] Indexes created.")
    end)
  end

  defp create_indexes do
    mongo = :mongo

    # accounts — unique on account_id, email, username
    Mongo.create_indexes(mongo, "accounts", [
      [key: [account_id: 1], name: "accounts_account_id", unique: true],
      [key: [email: 1], name: "accounts_email", unique: true],
      [key: [username: 1], name: "accounts_username", unique: true],
      [key: [discord_id: 1], name: "accounts_discord_id"]
    ])

    # profiles — compound index on (account_id, type)
    Mongo.create_indexes(mongo, "profiles", [
      [key: [account_id: 1, type: 1], name: "profiles_account_type", unique: true],
      [key: [account_id: 1], name: "profiles_account_id"]
    ])

    # items — compound index on (account_id, profile_id, template_id)
    Mongo.create_indexes(mongo, "items", [
      [key: [account_id: 1, profile_id: 1, template_id: 1], name: "items_composite", unique: true],
      [key: [account_id: 1, profile_id: 1], name: "items_account_profile"],
      [key: [account_id: 1, profile_id: 1, is_stat: 1], name: "items_account_profile_stat"]
    ])

    # tokens
    Mongo.create_indexes(mongo, "tokens", [
      [key: [token: 1], name: "tokens_token", unique: true],
      [key: [account_id: 1, type: 1], name: "tokens_account_type"]
    ])

    # friends — compound unique on (account_id, friend_id)
    Mongo.create_indexes(mongo, "friends", [
      [key: [account_id: 1, friend_id: 1], name: "friends_composite", unique: true],
      [key: [account_id: 1], name: "friends_account_id"],
      [key: [account_id: 1, status: 1], name: "friends_account_status"]
    ])
  end
end
