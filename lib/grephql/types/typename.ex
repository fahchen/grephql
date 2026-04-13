defmodule Grephql.Types.Typename do
  @moduledoc """
  Ecto Type for GraphQL `__typename` fields.

  Converts GraphQL type name strings (e.g., `"User"`, `"SearchResult"`)
  to snake_cased Elixir atoms (e.g., `:user`, `:search_result`).

  This type is automatically applied to `__typename` fields in generated
  union/interface schemas.
  """

  use Ecto.Type

  @type t() :: atom()

  @impl Ecto.Type
  def type, do: :string

  @impl Ecto.Type
  def cast(nil), do: {:ok, nil}

  def cast(value) when is_binary(value) do
    {:ok, to_atom(value)}
  end

  def cast(value) when is_atom(value), do: {:ok, value}

  def cast(_other), do: :error

  @impl Ecto.Type
  def load(nil), do: {:ok, nil}

  def load(value) when is_binary(value) do
    {:ok, to_atom(value)}
  end

  def load(_other), do: :error

  @impl Ecto.Type
  def dump(nil), do: {:ok, nil}

  def dump(value) when is_atom(value), do: {:ok, Atom.to_string(value)}

  def dump(value) when is_binary(value), do: {:ok, value}

  def dump(_other), do: :error

  # Type names from GraphQL schema, bounded set
  # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
  defp to_atom(value), do: value |> Macro.underscore() |> String.to_atom()
end
