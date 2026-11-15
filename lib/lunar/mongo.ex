defmodule Lunar.Mongo do
  @moduledoc """
  Thin wrapper around the MongoDB driver providing a simplified API
  compatible with the patterns used throughout Lunar's controllers.
  """
  @mongo_name :mongo

  # ---------------------------------------------------------------------------
  # Connection
  # ---------------------------------------------------------------------------

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  def start_link(opts \\ []) do
    url = Keyword.get(opts, :url, "mongodb://localhost:27017/lunar")
    {:ok, _} = Mongo.start_link(name: @mongo_name, url: url)
  end

  # ---------------------------------------------------------------------------
  # Read operations
  # ---------------------------------------------------------------------------

  @doc "Find a single document matching the filter. Returns map or nil."
  def find_one(collection, filter) when is_binary(collection) and is_map(filter) do
    case Mongo.find_one(@mongo_name, collection, filter) do
      nil  -> nil
      doc  -> atomize_doc(doc) |> Map.put(:__collection__, collection)
    end
  end

  @doc "Find all documents matching the filter. Returns list of maps."
  def find(collection, filter) when is_binary(collection) and is_map(filter) do
    Mongo.find(@mongo_name, collection, filter)
    |> Enum.to_list()
    |> Enum.map(fn doc -> atomize_doc(doc) |> Map.put(:__collection__, collection) end)
  end

  @doc "Count documents matching the filter."
  def count(collection, filter) when is_binary(collection) and is_map(filter) do
    Mongo.count(@mongo_name, collection, filter)
  end

  # ---------------------------------------------------------------------------
  # Write operations
  # ---------------------------------------------------------------------------

  @doc "Insert a document. Returns the document with _id."
  def insert_one(collection, doc) when is_binary(collection) and is_map(doc) do
    clean_doc = Map.drop(doc, [:__collection__, "__collection__"])
    {:ok, result} = Mongo.insert_one(@mongo_name, collection, clean_doc)
    Map.put(doc, :_id, result.inserted_id)
  end

  @doc "Insert many documents."
  def insert_many(collection, docs) when is_binary(collection) and is_list(docs) do
    {:ok, _} = Mongo.insert_many(@mongo_name, collection, docs)
    :ok
  end

  @doc "Update a single document matching the filter with $set changes."
  def update_one(collection, filter, set_changes) when is_binary(collection) do
    set_map = if Map.has_key?(set_changes, "$set"), do: set_changes, else: %{"$set" => set_changes}
    {:ok, _} = Mongo.update_one(@mongo_name, collection, filter, set_map)
    :ok
  end

  @doc "Delete a single document matching the filter."
  def delete_one(collection, filter) when is_binary(collection) and is_map(filter) do
    {:ok, _} = Mongo.delete_one(@mongo_name, collection, filter)
    :ok
  end

  @doc "Replace a single document (upsert)."
  def replace_one(collection, filter, replacement) when is_binary(collection) do
    {:ok, _} = Mongo.replace_one(@mongo_name, collection, filter, replacement, upsert: true)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Convenience helpers used as drop-in replacements for Ecto patterns
  # ---------------------------------------------------------------------------

  @doc "Like Repo.get_by — finds one document by exact field matches."
  def get_by(collection, conditions) when is_binary(collection) and is_map(conditions) do
    find_one(collection, conditions)
  end

  # ---------------------------------------------------------------------------
  # LIKE query helper — converts SQL LIKE patterns to Mongo regex.
  # "Quest:AthenaDaily%" becomes "^Quest:AthenaDaily"
  # ---------------------------------------------------------------------------
  def like_to_regex(pattern) do
    regex = pattern
      |> String.replace("%", ".*")
      |> String.replace("_", ".")
    %{"$regex" => "^#{String.replace(regex, "^.*", "")}", "$options" => "i"}
  end

  # Convert BSON document keys from strings to atoms where possible.
  defp atomize_doc(doc) when is_map(doc) do
    doc
    |> Map.new(fn {k, v} ->
      key = if is_binary(k), do: String.to_atom(k), else: k
      {key, atomize_value(v)}
    end)
  end
  defp atomize_doc(nil), do: nil

  defp atomize_value(v) when is_map(v), do: atomize_doc(v)
  defp atomize_value(v) when is_list(v), do: Enum.map(v, &atomize_value/1)
  defp atomize_value(v), do: v
end
