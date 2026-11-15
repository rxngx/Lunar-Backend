defmodule Lunar.Database.Tables.Tokens do
  @collection "tokens"

  def collection, do: @collection

  defstruct [:_id, :account_id, :token, :type, :created]

  def to_map(%__MODULE__{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:_id])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
