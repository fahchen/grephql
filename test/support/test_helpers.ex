defmodule Grephql.Test.Helpers do
  @moduledoc false

  @spec errors_on(Ecto.Changeset.t(), atom()) :: [String.t()]
  def errors_on(changeset, field) do
    changeset.errors
    |> Keyword.get_values(field)
    |> Enum.map(fn {msg, _opts} -> msg end)
  end
end
