defmodule TypedGql.Types.Typename do
  @moduledoc """
  Parameterized Ecto Type for GraphQL `__typename` fields.

  Converts GraphQL type name strings (e.g., `"User"`, `"SearchResult"`)
  to snake_cased Elixir atoms (e.g., `:user`, `:search_result`).

  Both directions of the mapping are pre-computed at compile time in `init/1`,
  so at runtime `cast/2`, `load/3` and `dump/3` perform only a `Map.fetch/2`
  lookup and `dump/3` is the inverse of `load/3`.

  ## Usage in schema

      field :__typename, TypedGql.Types.Typename, values: ["User", "Post"]

  Ecto calls `init/1` automatically with the field options.
  """

  use Ecto.ParameterizedType

  @type t() :: atom()

  @impl Ecto.ParameterizedType
  def init(opts) do
    string_to_atom =
      opts
      |> Keyword.fetch!(:values)
      |> Map.new(fn val ->
        # Type names from GraphQL schema, bounded set
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        {val, val |> Macro.underscore() |> String.to_atom()}
      end)

    atom_to_string = Map.new(string_to_atom, fn {name, atom} -> {atom, name} end)

    # Two distinct type names underscoring to one atom would make dump/3 pick a
    # winner silently, so load |> dump could answer with a name the server
    # never sent. Refuse the ambiguity where it is created.
    if map_size(atom_to_string) != map_size(string_to_atom) do
      colliding =
        string_to_atom
        |> Enum.group_by(fn {_name, atom} -> atom end, fn {name, _atom} -> name end)
        |> Enum.filter(fn {_atom, names} -> length(names) > 1 end)
        |> Enum.map_join("; ", fn {atom, names} ->
          "#{names |> Enum.sort() |> Enum.join(" and ")} both underscore to :#{atom}"
        end)

      raise ArgumentError, "ambiguous __typename values: #{colliding}"
    end

    %{string_to_atom: string_to_atom, atom_to_string: atom_to_string}
  end

  @impl Ecto.ParameterizedType
  def type(_params), do: :string

  @impl Ecto.ParameterizedType
  def cast(nil, _params), do: {:ok, nil}

  def cast(value, params) when is_binary(value), do: Map.fetch(params.string_to_atom, value)

  def cast(value, params) when is_atom(value) do
    if Map.has_key?(params.atom_to_string, value), do: {:ok, value}, else: :error
  end

  def cast(_other, _params), do: :error

  @impl Ecto.ParameterizedType
  def load(nil, _loader, _params), do: {:ok, nil}

  def load(value, _loader, params) when is_binary(value),
    do: Map.fetch(params.string_to_atom, value)

  def load(_other, _loader, _params), do: :error

  @impl Ecto.ParameterizedType
  def dump(nil, _dumper, _params), do: {:ok, nil}

  def dump(value, _dumper, params) when is_atom(value),
    do: Map.fetch(params.atom_to_string, value)

  def dump(_other, _dumper, _params), do: :error

  @impl Ecto.ParameterizedType
  def embed_as(_format, _params), do: :dump
end
