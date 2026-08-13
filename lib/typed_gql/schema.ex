defmodule TypedGql.Schema do
  @moduledoc false
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

  # Introspection meta-fields exist on the query root per the spec, but an
  # introspection result never lists them among Query's own fields.
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
