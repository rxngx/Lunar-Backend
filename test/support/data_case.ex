defmodule Lunar.DataCase do
  @moduledoc """
  Test case template for tests requiring access to MongoDB.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Lunar.Mongo
      alias Lunar.DB
      import Lunar.DataCase
    end
  end

  setup _tags do
    :ok
  end
end
