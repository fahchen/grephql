defmodule TypedGql.SchemaTest do
  use ExUnit.Case, async: true

  alias TypedGql.Schema
  alias TypedGql.Schema.Field
  alias TypedGql.Schema.InputValue
  alias TypedGql.Schema.Type
  alias TypedGql.Schema.TypeRef

  @schema %Schema{
    query_type: "Query",
    types: %{
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields: %{
          "user" => %Field{
            name: "user",
            type: %TypeRef{kind: :object, name: "User"}
          }
        }
      },
      "User" => %Type{
        kind: :object,
        name: "User",
        fields: %{
          "name" => %Field{name: "name", type: %TypeRef{kind: :scalar, name: "String"}}
        }
      }
    }
  }

  describe "get_type/2" do
    test "returns type by name" do
      assert {:ok, %Type{name: "Query"}} = Schema.get_type(@schema, "Query")
    end

    test "returns :error for unknown type" do
      assert :error = Schema.get_type(@schema, "Unknown")
    end
  end

  describe "get_field/3" do
    test "returns field by type and field name" do
      assert {:ok, %Field{name: "user"}} = Schema.get_field(@schema, "Query", "user")
    end

    test "returns :error for unknown field" do
      assert :error = Schema.get_field(@schema, "Query", "unknown")
    end

    test "returns :error for unknown type" do
      assert :error = Schema.get_field(@schema, "Unknown", "user")
    end

    # An introspection result never lists these among Query's own fields, but the
    # spec puts them on the query root.
    test "synthesizes __schema and __type on the query root" do
      assert {:ok, schema_field} = Schema.get_field(@schema, "Query", "__schema")

      assert %Field{
               name: "__schema",
               type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :object, name: "__Schema"}}
             } = schema_field

      assert {:ok, type_field} = Schema.get_field(@schema, "Query", "__type")

      assert %Field{
               name: "__type",
               type: %TypeRef{kind: :object, name: "__Type"},
               args: %{
                 "name" => %InputValue{
                   name: "name",
                   type: %TypeRef{
                     kind: :non_null,
                     of_type: %TypeRef{kind: :scalar, name: "String"}
                   }
                 }
               }
             } = type_field
    end

    test "does not synthesize them on any other type" do
      # A type the fixture really declares, so this fails if the synthesis is
      # not restricted to the query root.
      assert {:ok, %Field{}} = Schema.get_field(@schema, "User", "name")
      assert :error = Schema.get_field(@schema, "User", "__schema")
      assert :error = Schema.get_field(@schema, "User", "__type")
    end

    test "a schema that declares __schema itself wins" do
      declared = %Field{name: "__schema", type: %TypeRef{kind: :scalar, name: "String"}}

      schema = %{
        @schema
        | types:
            Map.update!(@schema.types, "Query", fn type ->
              %{type | fields: Map.put(type.fields, "__schema", declared)}
            end)
      }

      assert {:ok, ^declared} = Schema.get_field(schema, "Query", "__schema")
    end
  end
end
