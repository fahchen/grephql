defmodule Grephql.Test.SchemaHelper do
  @moduledoc false

  alias Grephql.Schema
  alias Grephql.Schema.Field
  alias Grephql.Schema.Type
  alias Grephql.Schema.TypeRef

  @spec build_schema(keyword()) :: Schema.t()
  def build_schema(opts \\ []) do
    %Schema{
      query_type: Keyword.get(opts, :query_type, "Query"),
      mutation_type: Keyword.get(opts, :mutation_type),
      subscription_type: Keyword.get(opts, :subscription_type),
      types: Keyword.get(opts, :types, default_types()),
      directives: Keyword.get(opts, :directives, [])
    }
  end

  @spec default_types() :: %{String.t() => Type.t()}
  def default_types do
    %{
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields: %{
          "user" => %Field{
            name: "user",
            type: %TypeRef{
              kind: :non_null,
              of_type: %TypeRef{kind: :object, name: "User"}
            },
            args: %{}
          },
          "users" => %Field{
            name: "users",
            type: %TypeRef{
              kind: :list,
              of_type: %TypeRef{kind: :object, name: "User"}
            },
            args: %{}
          }
        }
      },
      "User" => %Type{
        kind: :object,
        name: "User",
        fields: %{
          "id" => %Field{
            name: "id",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
          },
          "name" => %Field{
            name: "name",
            type: %TypeRef{kind: :scalar, name: "String"}
          },
          "email" => %Field{
            name: "email",
            type: %TypeRef{kind: :scalar, name: "String"}
          }
        }
      },
      "String" => %Type{kind: :scalar, name: "String"},
      "ID" => %Type{kind: :scalar, name: "ID"},
      "Boolean" => %Type{kind: :scalar, name: "Boolean"},
      "Int" => %Type{kind: :scalar, name: "Int"}
    }
  end
end
