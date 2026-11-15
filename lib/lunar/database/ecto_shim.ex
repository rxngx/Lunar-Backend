defmodule Ecto.Changeset do
  @moduledoc """
  Minimal shim for Ecto.Changeset.change/2 — stores {entity, changes}
  so Lunar.Repo.update!/1 can apply them to MongoDB.
  """

  def change(entity, changes) when is_map(changes) do
    {entity, changes}
  end

  def change(entity, changes) when is_list(changes) do
    {entity, Map.new(changes)}
  end

  # No-op traverse_errors for test compatibility
  def traverse_errors(_, _), do: %{}
end
