defmodule Lunar.Database.Tables.Hotfixes do
  @collection "hotfixes"

  def collection, do: @collection

  @derive {Jason.Encoder, only: [:id, :filename, :value, :enabled]}
  defstruct [:_id, :id, :filename, :value, enabled: true]

  def to_map(%__MODULE__{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:_id])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
