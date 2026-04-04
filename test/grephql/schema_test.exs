defmodule Grephql.SchemaTest do
  use ExUnit.Case, async: true

  alias Grephql.Schema
  alias Grephql.Schema.Field
  alias Grephql.Schema.Type
  alias Grephql.Schema.TypeRef

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
  end
end
