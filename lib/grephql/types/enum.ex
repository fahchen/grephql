defmodule Grephql.Types.Enum do
  @moduledoc """
  Parameterized Ecto Type for GraphQL enum types.

  Converts between GraphQL enum strings (e.g., `"ACTIVE"`, `"active"`)
  and downcased Elixir atoms (e.g., `:active`). Supports case-insensitive
  matching on cast/load — `"FOO"`, `"Foo"`, and `"foo"` all resolve to
  the same atom.

  ## Usage in schema

      field :role, Grephql.Types.Enum, values: ["ADMIN", "USER", "GUEST"]

  Ecto calls `init/1` automatically with the field options.
  """

  use Ecto.ParameterizedType

  @type t() :: atom()

  @impl Ecto.ParameterizedType
  def init(opts) do
    values = Keyword.fetch!(opts, :values)

    # Build lookup maps:
    # - downcase_to_original: "admin" => "ADMIN" (for case-insensitive lookup)
    # - original_to_atom: "ADMIN" => :admin (for exact match fast path)
    # - atom_to_original: :admin => "ADMIN" (for dump)
    {downcase_to_original, original_to_atom, atom_to_original} =
      Enum.reduce(values, {%{}, %{}, %{}}, fn val, {d2o, o2a, a2o} ->
        # Enum values from GraphQL schema, bounded set
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        atom_val = val |> Macro.underscore() |> String.to_atom()
        downcased = String.downcase(val)

        {Map.put(d2o, downcased, val), Map.put(o2a, val, atom_val), Map.put(a2o, atom_val, val)}
      end)

    %{
      downcase_to_original: downcase_to_original,
      original_to_atom: original_to_atom,
      atom_to_original: atom_to_original
    }
  end

  @impl Ecto.ParameterizedType
  def type(_params), do: :string

  @impl Ecto.ParameterizedType
  def cast(nil, _params), do: {:ok, nil}

  def cast(value, params) when is_binary(value) do
    case Map.fetch(params.original_to_atom, value) do
      {:ok, _atom} = ok ->
        ok

      :error ->
        case Map.fetch(params.downcase_to_original, String.downcase(value)) do
          {:ok, original} -> Map.fetch(params.original_to_atom, original)
          :error -> :error
        end
    end
  end

  def cast(value, params) when is_atom(value) do
    if Map.has_key?(params.atom_to_original, value), do: {:ok, value}, else: :error
  end

  def cast(_other, _params), do: :error

  @impl Ecto.ParameterizedType
  def dump(nil, _dumper, _params), do: {:ok, nil}

  def dump(value, _dumper, params) when is_atom(value) do
    case Map.fetch(params.atom_to_original, value) do
      {:ok, _string} = ok -> ok
      :error -> :error
    end
  end

  def dump(_other, _dumper, _params), do: :error

  @impl Ecto.ParameterizedType
  def load(nil, _loader, _params), do: {:ok, nil}

  def load(value, _loader, params) when is_binary(value) do
    case Map.fetch(params.downcase_to_original, String.downcase(value)) do
      {:ok, original} -> Map.fetch(params.original_to_atom, original)
      :error -> :error
    end
  end

  def load(_other, _loader, _params), do: :error

  @impl Ecto.ParameterizedType
  def embed_as(_format, _params), do: :dump
end
