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

  Custom scalars map to user-provided `Ecto.Type` modules via the `scalar_types` config.
  Custom scalars override built-in defaults. Unknown scalars raise `CompileError`.
  """

  alias Grephql.Schema.TypeRef

  @builtin_scalars %{
    "String" => :string,
    "Int" => :integer,
    "Float" => :float,
    "Boolean" => :boolean,
    "ID" => :string,
    "DateTime" => Grephql.Types.DateTime
  }

  @type scalar_types() :: %{String.t() => module()}

  @type ecto_type() ::
          :string
          | :integer
          | :float
          | :boolean
          | {:array, ecto_type()}
          | {:object, String.t()}
          | module()

  @type resolve_result() :: %{
          ecto_type: ecto_type(),
          nullable: boolean()
        }

  @doc """
  Resolves a GraphQL type reference to its Ecto type and nullability.

  Returns a map with:
    - `:ecto_type` — the Ecto type for schema field definition
    - `:nullable` — whether the field allows nil

  ## Parameters

    - `type_ref` — the GraphQL type reference to resolve
    - `scalar_types` — user-provided custom scalar mappings (default: `%{}`)
  """
  @spec resolve(TypeRef.t(), scalar_types()) :: resolve_result()
  def resolve(%TypeRef{kind: :non_null, of_type: inner}, scalar_types) do
    %{ecto_type: resolve_inner(inner, scalar_types), nullable: false}
  end

  def resolve(%TypeRef{} = type_ref, scalar_types) do
    %{ecto_type: resolve_inner(type_ref, scalar_types), nullable: true}
  end

  defp resolve_inner(%TypeRef{kind: :list, of_type: inner}, scalar_types) do
    {:array, resolve(inner, scalar_types).ecto_type}
  end

  defp resolve_inner(%TypeRef{kind: kind, name: name}, scalar_types)
       when kind in [:scalar, :enum] do
    resolve_scalar(name, scalar_types)
  end

  defp resolve_inner(%TypeRef{kind: kind, name: name}, _scalar_types)
       when kind in [:object, :interface, :union, :input_object] do
    {:object, name}
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
end
