defmodule Grephql.Types.Union do
  @moduledoc """
  Dynamic parameterized Ecto Type for GraphQL union/interface types.

  Dispatches to the correct embedded schema module based on the
  `__typename` field in the JSON map.

  ## Usage

      Grephql.Types.Union.define(MyApp.SearchUnion, %{
        "User" => MyApp.Search.User,
        "Post" => MyApp.Search.Post
      })

  The generated module implements `Ecto.ParameterizedType` and uses
  `embed_as: :dump` so that `Ecto.embedded_load/3` calls `load/3`,
  which reads `__typename` and delegates to the matched module via
  `Ecto.embedded_load/3`.
  """

  @doc """
  Defines a parameterized Ecto Type module for a GraphQL union/interface.

  `typename_to_module` maps GraphQL `__typename` strings to their
  corresponding embedded schema modules.
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

      @type t() :: struct()

      @impl Ecto.ParameterizedType
      def init(_opts), do: %{}

      @impl Ecto.ParameterizedType
      def type(_params), do: :map

      @impl Ecto.ParameterizedType
      def cast(nil, _params), do: {:ok, nil}

      def cast(%{__struct__: _module} = struct, _params), do: {:ok, struct}

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

      def dump(%{__struct__: _module} = struct, _dumper, _params),
        do: {:ok, Map.from_struct(struct)}

      def dump(_other, _dumper, _params), do: :error

      @impl Ecto.ParameterizedType
      def embed_as(_format, _params), do: :dump

      defp resolve_module(%{"__typename" => typename}) do
        case Map.fetch(@typename_to_module, typename) do
          {:ok, _module} = ok -> ok
          :error -> {:error, "unknown __typename: #{inspect(typename)}"}
        end
      end

      defp resolve_module(_map), do: {:error, "missing __typename field"}
    end
  end
end
