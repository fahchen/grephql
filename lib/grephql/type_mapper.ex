defmodule Grephql.TypeMapper do
  @moduledoc """
  Maps GraphQL type references to Ecto schema types.

  Resolves the corresponding Ecto type (for embedded schema field definitions)
  and nullability from a parsed GraphQL type reference.

  ## Scalar mapping

  Built-in GraphQL scalars map to Ecto primitives:

    - `String` → `:string`
    - `Int` → `:integer`
    - `Float` → `:float`
    - `Boolean` → `:boolean`
    - `ID` → `:string`
    - `DateTime` → `Grephql.Types.DateTime`
    - `Date` → `:date`
    - `JSON` / `JSONObject` → `:map`
    - `URI` / `URL` → `:string`
    - `BigInt` / `Long` → `:integer`
    - `HTML` → `:string`
    - `UnsignedInt64` → `:integer`
    - `Base64String` → `:string`

  Custom scalars map to user-provided `Ecto.Type` modules via the `scalar_types` config.
  Custom scalars override built-in defaults. Unknown scalars raise `CompileError`.

  ## Enum mapping

  Enum types are automatically resolved using `Grephql.Types.Enum` (a parameterized
  Ecto type). No user configuration is needed — enum values are read from the schema
  at compile time. Users can still override enum types via `scalar_types` if custom
  serialization is needed.
  """

  alias Grephql.Schema
  alias Grephql.Schema.TypeRef

  @builtin_scalars %{
    "String" => :string,
    "Int" => :integer,
    "Float" => :float,
    "Boolean" => :boolean,
    "ID" => :string,
    "DateTime" => Grephql.Types.DateTime,
    "Date" => :date,
    "JSON" => :map,
    "JSONObject" => :map,
    "URI" => :string,
    "URL" => :string,
    "BigInt" => :integer,
    "Long" => :integer,
    "HTML" => :string,
    "UnsignedInt64" => :integer,
    "Base64String" => :string
  }

  @type scalar_types() :: %{String.t() => module()}

  @type ecto_type() ::
          :string
          | :integer
          | :float
          | :boolean
          | :date
          | :map
          | {:array, ecto_type()}
          | {:object, String.t()}
          | module()

  @type resolve_result() :: %{
          ecto_type: ecto_type(),
          nullable: boolean(),
          enum_values: [String.t()] | nil
        }

  @doc """
  Resolves a GraphQL type reference to its Ecto type and nullability.

  Returns a map with:
    - `:ecto_type` — the Ecto type for schema field definition
    - `:nullable` — whether the field allows nil
    - `:enum_values` — enum value strings when type is `Grephql.Types.Enum`, nil otherwise

  ## Parameters

    - `type_ref` — the GraphQL type reference to resolve
    - `schema` — the parsed GraphQL schema (for enum value lookup)
    - `scalar_types` — user-provided custom scalar mappings (default: `%{}`)
  """
  @spec resolve(TypeRef.t(), Schema.t(), scalar_types()) :: resolve_result()
  def resolve(%TypeRef{kind: :non_null, of_type: inner}, schema, scalar_types) do
    %{resolve_inner(inner, schema, scalar_types) | nullable: false}
  end

  def resolve(%TypeRef{} = type_ref, schema, scalar_types) do
    %{resolve_inner(type_ref, schema, scalar_types) | nullable: true}
  end

  defp resolve_inner(%TypeRef{kind: :list, of_type: inner}, schema, scalar_types) do
    default_result({:array, resolve(inner, schema, scalar_types).ecto_type})
  end

  defp resolve_inner(%TypeRef{kind: :scalar, name: name}, _schema, scalar_types) do
    default_result(resolve_scalar(name, scalar_types))
  end

  defp resolve_inner(%TypeRef{kind: :enum, name: name}, schema, scalar_types) do
    resolve_enum(name, schema, scalar_types)
  end

  defp resolve_inner(%TypeRef{kind: kind, name: name}, _schema, _scalar_types)
       when kind in [:object, :interface, :union, :input_object] do
    default_result({:object, name})
  end

  defp default_result(ecto_type) do
    %{ecto_type: ecto_type, nullable: true, enum_values: nil}
  end

  defp resolve_scalar(name, scalar_types) do
    with :error <- Map.fetch(scalar_types, name),
         :error <- Map.fetch(@builtin_scalars, name) do
      raise CompileError,
        description: "unknown scalar type #{inspect(name)}, configure it via scalar_types"
    else
      {:ok, type} -> type
    end
  end

  defp resolve_enum(name, schema, scalar_types) do
    # User override takes priority
    case Map.fetch(scalar_types, name) do
      {:ok, type} ->
        default_result(type)

      :error ->
        {:ok, type} = Schema.get_type(schema, name)
        values = Enum.map(type.enum_values, & &1.name)
        %{ecto_type: Grephql.Types.Enum, nullable: true, enum_values: values}
    end
  end
end
