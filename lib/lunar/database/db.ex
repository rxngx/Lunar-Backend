defmodule Lunar.DB do
  @moduledoc """
  Thin convenience functions over Lunar.Mongo used throughout controllers.
  Replaces Ecto.Repo patterns with direct MongoDB calls.
  """

  alias Lunar.Mongo
  alias Lunar.Database.Tables.{Items, Profiles}

  # ---------------------------------------------------------------------------
  # Items
  # ---------------------------------------------------------------------------

  def insert_item(fields) when is_map(fields) do
    Mongo.insert_one(Items.collection(), fields)
  end

  def update_item_field(item, field, value) when is_map(item) do
    Mongo.update_one(
      Items.collection(),
      %{_id: item[:_id]},
      %{"$set" => %{field => value}}
    )
    Map.put(item, field, value)
  end

  def update_item_fields(item, changes) when is_map(item) and is_map(changes) do
    Mongo.update_one(
      Items.collection(),
      %{_id: item[:_id]},
      %{"$set" => changes}
    )
    Map.merge(item, changes)
  end

  def delete_item(item) when is_map(item) do
    Mongo.delete_one(Items.collection(), %{_id: item[:_id]})
  end

  def find_item(account_id, profile_id, template_id) do
    Mongo.find_one(Items.collection(), %{
      account_id: account_id,
      profile_id: profile_id,
      template_id: template_id
    })
  end

  def find_items(account_id, profile_id, is_stat) do
    Mongo.find(Items.collection(), %{
      account_id: account_id,
      profile_id: profile_id,
      is_stat: is_stat
    })
  end

  def find_items_regex(account_id, profile_id, template_prefix) do
    Mongo.find(Items.collection(), %{
      account_id: account_id,
      profile_id: profile_id,
      is_stat: false,
      template_id: %{"$regex" => "^#{Regex.escape(template_prefix)}", "$options" => "i"}
    })
  end

  def find_mtx(account_id, profile_id \\ "common_core") do
    Mongo.find_one(Items.collection(), %{
      account_id: account_id,
      profile_id: profile_id,
      is_stat: false,
      template_id: %{"$regex" => "^Currency:Mtx", "$options" => "i"}
    })
  end

  # ---------------------------------------------------------------------------
  # Profiles
  # ---------------------------------------------------------------------------

  def find_profile(account_id, type) do
    Mongo.find_one(Profiles.collection(), %{account_id: account_id, type: type})
  end

  def bump_profile_revision(profile) when is_map(profile) do
    new_rev = (profile[:revision] || 0) + 1
    Mongo.update_one(Profiles.collection(), %{_id: profile[:_id]},
      %{"$set" => %{revision: new_rev}})
    Map.put(profile, :revision, new_rev)
  end

  # ---------------------------------------------------------------------------
  # Stats (is_stat: true items)
  # ---------------------------------------------------------------------------

  def upsert_stat(account_id, profile_id, key, value) do
    case find_item(account_id, profile_id, key) do
      nil ->
        insert_item(%{
          account_id: account_id,
          profile_id: profile_id,
          template_id: key,
          value: value,
          quantity: 1,
          is_stat: true
        })
      existing ->
        update_item_field(existing, :value, value)
    end
  end
end
