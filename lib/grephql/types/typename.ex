defmodule Grephql.Types.Typename do
  @moduledoc """
  Parameterized Ecto Type for GraphQL `__typename` fields.

  Converts GraphQL type name strings (e.g., `"User"`, `"SearchResult"`)
  to snake_cased Elixir atoms (e.g., `:user`, `:search_result`).

  The string-to-atom mapping is pre-computed at compile time in `init/1`.
  At runtime, `cast/2` and `load/3` perform only a `Map.fetch/2` lookup.

  ## Usage in schema

      field :__typename, Grephql.Types.Typename, values: ["User", "Post"]

  Ecto calls `init/1` automatically with the field options.
  """

  use Ecto.ParameterizedType

  @type t() :: atom()

  @impl Ecto.ParameterizedType
  def init(opts) do
    opts
    |> Keyword.fetch!(:values)
    |> Map.new(fn val ->
      # Type names from GraphQL schema, bounded set
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      {val, val |> Macro.underscore() |> String.to_atom()}
    end)
  end

  @impl Ecto.ParameterizedType
  def type(_params), do: :string

  @impl Ecto.ParameterizedType
  def cast(nil, _params), do: {:ok, nil}

  def cast(value, params) when is_binary(value), do: Map.fetch(params, value)

  def cast(value, _params) when is_atom(value), do: {:ok, value}

  def cast(_other, _params), do: :error

  @impl Ecto.ParameterizedType
  def load(nil, _loader, _params), do: {:ok, nil}

  def load(value, _loader, params) when is_binary(value), do: Map.fetch(params, value)

  def load(_other, _loader, _params), do: :error

  @impl Ecto.ParameterizedType
  def dump(nil, _dumper, _params), do: {:ok, nil}

  def dump(value, _dumper, _params) when is_atom(value), do: {:ok, Atom.to_string(value)}

  def dump(value, _dumper, _params) when is_binary(value), do: {:ok, value}

  def dump(_other, _dumper, _params), do: :error

  @impl Ecto.ParameterizedType
  def embed_as(_format, _params), do: :dump
end
