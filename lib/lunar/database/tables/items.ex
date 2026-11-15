defmodule Lunar.Database.Tables.Items do
  @collection "items"

  def collection, do: @collection

  defstruct [
    :_id,
    :account_id,
    :profile_id,
    :template_id,
    :value,
    quantity: 1,
    is_stat: false
  ]

  def to_map(%__MODULE__{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:_id])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
