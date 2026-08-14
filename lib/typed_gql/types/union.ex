defmodule TypedGql.Types.Union do
  @moduledoc """
  Dynamic parameterized Ecto Type for GraphQL union/interface types.

  Dispatches to the correct embedded schema module based on the
  `__typename` field in the JSON map.

  The generated module implements `Ecto.ParameterizedType` and uses
  `embed_as: :dump` so that `Ecto.embedded_load/3` calls `load/3`,
  which reads `__typename` and delegates to the matched module via
  `Ecto.embedded_load/3`.

  An unresolvable `__typename` returns `:error`, as the callback contract
  requires; Ecto turns that into its own `ArgumentError` naming the offending
  map, the field and the schema, so nothing is lost by not carrying a message.

  `cast/2` accepts the wire shape — a decoded JSON map with a string
  `"__typename"` — and reads the values inside the variant with load
  semantics, so an already-cast value such as an enum atom is not accepted.
  """

  @doc """
  Defines a parameterized Ecto Type module for a GraphQL union/interface.

  Called by the type generator at compile time. `typename_to_module` maps
  GraphQL `__typename` strings to their corresponding embedded schema modules.
  """
  @spec define(module(), %{String.t() => module()}) :: {:module, module(), binary(), term()}
  def define(module_name, typename_to_module)
      when is_atom(module_name) and is_map(typename_to_module) do
    Module.create(
      module_name,
      module_body(typename_to_module),
      Macro.Env.location(__ENV__)
    )
  end

  # Multiple function clauses required by Ecto.ParameterizedType behaviour
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp module_body(typename_to_module) do
    quote do
      use Ecto.ParameterizedType

      @typename_to_module unquote(Macro.escape(typename_to_module))
      @variant_modules unquote(Macro.escape(Map.values(typename_to_module)))

      @type t() :: struct()

      @impl Ecto.ParameterizedType
      def init(_opts), do: %{}

      @impl Ecto.ParameterizedType
      def type(_params), do: :map

      @impl Ecto.ParameterizedType
      def cast(nil, _params), do: {:ok, nil}

      # A struct is also a map, so this clause has to answer for non-members
      # itself: falling through to `cast(%{} = map, _params)` would report them
      # as a missing `__typename` instead of rejecting them.
      def cast(%{__struct__: module} = struct, _params) do
        if module in @variant_modules, do: {:ok, struct}, else: :error
      end

      def cast(%{} = map, _params) do
        with {:ok, module} <- resolve_module(map) do
          {:ok, Ecto.embedded_load(module, map, :json)}
        end
      end

      def cast(_other, _params), do: :error

      @impl Ecto.ParameterizedType
      def load(nil, _loader, _params), do: {:ok, nil}

      def load(%{} = map, _loader, _params) do
        with {:ok, module} <- resolve_module(map) do
          {:ok, Ecto.embedded_load(module, map, :json)}
        end
      end

      def load(_other, _loader, _params), do: :error

      @impl Ecto.ParameterizedType
      def dump(nil, _dumper, _params), do: {:ok, nil}

      # Delegating to the variant's own dumpers is what makes the result
      # JSON-encodable: enums become strings and nested embeds become maps.
      def dump(%{__struct__: module} = struct, _dumper, _params) do
        if module in @variant_modules,
          do: {:ok, Ecto.embedded_dump(struct, :json)},
          else: :error
      end

      def dump(_other, _dumper, _params), do: :error

      @impl Ecto.ParameterizedType
      def embed_as(_format, _params), do: :dump

      defp resolve_module(%{"__typename" => typename}),
        do: Map.fetch(@typename_to_module, typename)

      # `Ecto.embedded_dump/2` emits atom keys, so a dumped union has to resolve
      # too. The guard keeps a loaded variant struct, whose `:__typename` is an
      # atom, out of this clause.
      defp resolve_module(%{__typename: typename}) when is_binary(typename),
        do: Map.fetch(@typename_to_module, typename)

      defp resolve_module(_map), do: :error
    end
  end
end
