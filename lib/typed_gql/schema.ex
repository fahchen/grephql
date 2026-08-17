defmodule TypedGql.Schema do
  @moduledoc """
  A GraphQL schema loaded from an introspection result.

  This is what the server says it offers — the root operation types, every
  named type and every directive — and what queries are validated and
  generated against.
  """
  use TypedStructor

  alias TypedGql.Schema.Directive
  alias TypedGql.Schema.Type

  typed_structor do
    field :query_type, String.t()
    field :mutation_type, String.t()
    field :subscription_type, String.t()
    field :types, %{String.t() => Type.t()}, default: %{}
    field :directives, [Directive.t()], default: []
  end

  @spec get_type(t(), String.t()) :: {:ok, Type.t()} | :error
  def get_type(%__MODULE__{types: types}, name) do
    Map.fetch(types, name)
  end

  @doc """
  Whether `type_name` names an abstract type — a union or an interface.

  A name the schema does not define is not abstract; the callers that care
  about that distinction check existence separately.
  """
  @spec abstract?(t(), String.t()) :: boolean()
  def abstract?(%__MODULE__{} = schema, type_name) do
    match?({:ok, %{kind: kind}} when kind in [:union, :interface], get_type(schema, type_name))
  end

  # Introspection meta-fields exist on the query root per the spec, but an
  # introspection result never lists them among Query's own fields. Their
  # return types "__Schema"/"__Type" have to be present in the loaded schema
  # for a sub-selection to validate — a dump that strips meta types still gets
  # a clean validation error naming the missing type, not a crash.
  @root_introspection_fields %{
    "__schema" => %TypedGql.Schema.Field{
      name: "__schema",
      type: %TypedGql.Schema.TypeRef{
        kind: :non_null,
        of_type: %TypedGql.Schema.TypeRef{kind: :object, name: "__Schema"}
      }
    },
    "__type" => %TypedGql.Schema.Field{
      name: "__type",
      type: %TypedGql.Schema.TypeRef{kind: :object, name: "__Type"},
      args: %{
        "name" => %TypedGql.Schema.InputValue{
          name: "name",
          type: %TypedGql.Schema.TypeRef{
            kind: :non_null,
            of_type: %TypedGql.Schema.TypeRef{kind: :scalar, name: "String"}
          }
        }
      }
    }
  }

  @spec get_field(t(), String.t(), String.t()) ::
          {:ok, TypedGql.Schema.Field.t()} | :error
  def get_field(%__MODULE__{query_type: type_name} = schema, type_name, field_name)
      when is_map_key(@root_introspection_fields, field_name) do
    with :error <- lookup_field(schema, type_name, field_name) do
      Map.fetch(@root_introspection_fields, field_name)
    end
  end

  def get_field(%__MODULE__{} = schema, type_name, field_name) do
    lookup_field(schema, type_name, field_name)
  end

  defp lookup_field(schema, type_name, field_name) do
    with {:ok, type} <- get_type(schema, type_name) do
      Type.get_field(type, field_name)
    end
  end

  @spec get_directive(t(), String.t()) :: {:ok, Directive.t()} | :error
  def get_directive(%__MODULE__{directives: directives}, name) do
    case Enum.find(directives, &(&1.name == name)) do
      nil -> :error
      directive -> {:ok, directive}
    end
  end
end
