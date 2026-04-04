defmodule Grephql.Types.Enum do
  @moduledoc """
  Dynamic Ecto Type for GraphQL enum types.

  Converts between uppercase GraphQL enum strings (e.g., `"ACTIVE"`)
  and downcased Elixir atoms (e.g., `:active`).

  ## Usage

      Grephql.Types.Enum.define(MyApp.Enums.Role, ["ADMIN", "USER", "GUEST"])

  This defines a module `MyApp.Enums.Role` implementing `Ecto.Type` with:

    - `cast("ADMIN")` → `{:ok, :admin}`
    - `cast(:admin)` → `{:ok, :admin}`
    - `dump(:admin)` → `{:ok, "ADMIN"}`
    - `load("ADMIN")` → `{:ok, :admin}`
  """

  @doc """
  Defines an Ecto Type module for a GraphQL enum at the given module name.

  `values` is a list of uppercase GraphQL enum value strings.
  """
  @spec define(module(), [String.t()]) :: {:module, module(), binary(), term()}
  def define(module_name, values) when is_atom(module_name) and is_list(values) do
    pairs = Enum.map(values, fn val -> {downcase_atom(val), val} end)
    atom_to_string = Map.new(pairs)
    string_to_atom = Map.new(pairs, fn {atom, string} -> {string, atom} end)

    Module.create(
      module_name,
      module_body(atom_to_string, string_to_atom),
      Macro.Env.location(__ENV__)
    )
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp module_body(atom_to_string, string_to_atom) do
    quote do
      use Ecto.Type

      @atom_to_string unquote(Macro.escape(atom_to_string))
      @string_to_atom unquote(Macro.escape(string_to_atom))

      @impl Ecto.Type
      def type, do: :string

      @impl Ecto.Type
      def cast(value) when is_binary(value) do
        Map.fetch(@string_to_atom, value)
      end

      def cast(value) when is_atom(value) and is_map_key(@atom_to_string, value) do
        {:ok, value}
      end

      def cast(_other), do: :error

      @impl Ecto.Type
      def dump(value) when is_atom(value) do
        case Map.fetch(@atom_to_string, value) do
          {:ok, string} -> {:ok, string}
          :error -> :error
        end
      end

      def dump(_other), do: :error

      @impl Ecto.Type
      def load(value) when is_binary(value) do
        Map.fetch(@string_to_atom, value)
      end

      def load(_other), do: :error
    end
  end

  # Enum values are created at compile time from the GraphQL schema,
  # so String.to_atom is safe here (bounded set of known values).
  defp downcase_atom(value) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    value |> String.downcase() |> String.to_atom()
  end
end
