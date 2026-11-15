defmodule Lunar.Database.Tables.Accounts do
  @collection "accounts"

  def collection, do: @collection

  defstruct [
    :_id,
    :account_id,
    :email,
    :password,
    :username,
    :discord_id,
    banned: false,
    is_server: false
  ]

  def to_map(%__MODULE__{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:_id])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
