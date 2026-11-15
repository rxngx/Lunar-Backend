defmodule Lunar.Repo do
  @moduledoc """
  Compatibility shim — delegates to Lunar.Mongo so existing controllers
  that reference Lunar.Repo still work after the PostgreSQL → MongoDB migration.
  """

  defp collection_name(module) when is_atom(module), do: module.collection()
  defp collection_name(string) when is_binary(string), do: string

  defp get_collection(entity) when is_map(entity) do
    case Map.get(entity, :__collection__) do
      nil when is_map_key(entity, :__struct__) ->
        entity.__struct__ |> collection_name()
      coll when is_binary(coll) -> coll
      _ -> "items"  # fallback
    end
  end

  defp get_id(entity) when is_map(entity) do
    Map.get(entity, :_id) || Map.get(entity, "_id")
  end

  # --- get_by ---
  def get_by(coll, conditions) when is_map(conditions) do
    Lunar.Mongo.get_by(collection_name(coll), conditions)
  end

  # --- find_one / find ---
  def find_one(coll, filter), do: Lunar.Mongo.find_one(collection_name(coll), filter)
  def find(coll, filter), do: Lunar.Mongo.find(collection_name(coll), filter)

  # --- insert! ---
  # Accept %Schema{} struct
  def insert!(%{__struct__: module} = struct) when is_map(struct) do
    coll = module.collection()
    doc = struct |> Map.from_struct() |> Map.drop([:_id])
    Lunar.Mongo.insert_one(coll, doc)
  end

  # Accept plain map
  def insert!(doc) when is_map(doc) do
    coll = get_collection(doc)
    Lunar.Mongo.insert_one(coll, doc)
  end

  # --- update! ---
  # Accept {entity, changes} from Ecto.Changeset.change
  def update!({entity, changes}) when is_map(entity) and is_map(changes) do
    coll = get_collection(entity)
    id = get_id(entity)
    Lunar.Mongo.update_one(coll, %{_id: id}, %{"$set" => changes})
    Map.merge(entity, changes)
  end

  # Accept entity + changes directly
  def update!(entity, changes) when is_map(entity) and is_map(changes) do
    coll = get_collection(entity)
    id = get_id(entity)
    Lunar.Mongo.update_one(coll, %{_id: id}, %{"$set" => changes})
    Map.merge(entity, changes)
  end

  # --- delete! ---
  def delete!(entity) when is_map(entity) do
    coll = get_collection(entity)
    id = get_id(entity)
    Lunar.Mongo.delete_one(coll, %{_id: id})
    :ok
  end

  # --- count ---
  def count(coll, filter), do: Lunar.Mongo.count(collection_name(coll), filter)

  # --- transaction (no-op for Mongo) ---
  def transaction(fun) when is_function(fun, 0), do: fun.()
  def transaction(fun) when is_function(fun, 1), do: fun.(%{})

  # --- aggregate stubs ---
  def aggregate(_, _, _), do: 0
end
