defmodule Grephql.Validator.Rules.FragmentsTest do
  use ExUnit.Case, async: true

  alias Grephql.Schema.Field, as: SchemaField
  alias Grephql.Schema.Type
  alias Grephql.Schema.TypeRef
  alias Grephql.Test.SchemaHelper
  alias Grephql.Validator.Context
  alias Grephql.Validator.Rules.Fragments

  describe "type condition existence" do
    test "known type passes" do
      ctx = validate(~s|query { user(id: "1") { ... on User { name } } }|)
      assert errors(ctx) == []
    end

    test "unknown type fails" do
      ctx = validate(~s|query { user(id: "1") { ... on Unknown { name } } }|)
      assert [error] = errors(ctx)
      assert error.message =~ "type \"Unknown\" in type condition does not exist"
    end
  end

  describe "fragment type condition kind" do
    test "fragment on scalar type fails" do
      query = """
      query { user(id: "1") { name } }
      fragment BadFrag on String { length }
      """

      ctx = validate(query)
      assert [error] = errors(ctx)
      assert error.message =~ "fragment \"BadFrag\" cannot be defined on scalar type \"String\""
    end
  end

  describe "type condition applicability" do
    test "same type passes" do
      ctx = validate(~s|query { user(id: "1") { ... on User { name } } }|)
      assert errors(ctx) == []
    end

    test "member of union passes" do
      types = types_with_union()
      ctx = validate(~s|query { search { ... on User { name } } }|, types: types)
      assert errors(ctx) == []
    end

    test "non-member of union fails" do
      types = types_with_union()
      ctx = validate(~s|query { search { ... on Query { user } } }|, types: types)
      applicability_errors = Enum.filter(errors(ctx), &(&1.message =~ "not applicable"))
      assert [error] = applicability_errors
      assert error.message =~ "type \"Query\" is not applicable to \"SearchResult\""
    end

    test "member of interface passes" do
      types = types_with_interface()
      ctx = validate(~s|query { node { ... on User { name } } }|, types: types)
      assert errors(ctx) == []
    end

    test "non-member of interface fails" do
      types = types_with_interface()
      ctx = validate(~s|query { node { ... on Query { user } } }|, types: types)
      applicability_errors = Enum.filter(errors(ctx), &(&1.message =~ "not applicable"))
      assert [error] = applicability_errors
      assert error.message =~ "type \"Query\" is not applicable to \"Node\""
    end

    test "inline fragment without type condition passes" do
      ctx = validate(~s|query { user(id: "1") { ... { name } } }|)
      assert errors(ctx) == []
    end
  end

  defp parse!(query) do
    {:ok, doc} = Grephql.Parser.parse(query)
    doc
  end

  defp validate(query, schema_opts \\ []) do
    schema = SchemaHelper.build_schema(schema_opts)
    ctx = %Context{schema: schema}
    Fragments.validate(parse!(query), ctx)
  end

  defp errors(ctx), do: Context.errors_by_severity(ctx, :error)

  defp types_with_union do
    Map.merge(SchemaHelper.default_types(), %{
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields: %{
          "user" => %SchemaField{
            name: "user",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :object, name: "User"}},
            args: %{
              "id" => %Grephql.Schema.InputValue{
                name: "id",
                type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
              }
            }
          },
          "search" => %SchemaField{
            name: "search",
            type: %TypeRef{kind: :union, name: "SearchResult"},
            args: %{}
          }
        }
      },
      "SearchResult" => %Type{
        kind: :union,
        name: "SearchResult",
        possible_types: ["User", "Post"]
      },
      "Post" => %Type{
        kind: :object,
        name: "Post",
        fields: %{
          "title" => %SchemaField{
            name: "title",
            type: %TypeRef{kind: :scalar, name: "String"}
          }
        }
      }
    })
  end

  defp types_with_interface do
    Map.merge(SchemaHelper.default_types(), %{
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields: %{
          "user" => %SchemaField{
            name: "user",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :object, name: "User"}},
            args: %{
              "id" => %Grephql.Schema.InputValue{
                name: "id",
                type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
              }
            }
          },
          "node" => %SchemaField{
            name: "node",
            type: %TypeRef{kind: :interface, name: "Node"},
            args: %{}
          }
        }
      },
      "Node" => %Type{
        kind: :interface,
        name: "Node",
        possible_types: ["User"],
        fields: %{
          "id" => %SchemaField{
            name: "id",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
          }
        }
      }
    })
  end
end
