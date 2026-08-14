defmodule TypedGql.Validator.Rules.FragmentsTest do
  use ExUnit.Case, async: true

  alias TypedGql.Schema.Field, as: SchemaField
  alias TypedGql.Schema.Type
  alias TypedGql.Schema.TypeRef
  alias TypedGql.Test.SchemaHelper
  alias TypedGql.Validator.Context
  alias TypedGql.Validator.Rules.Fragments

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

  # Spec 5.5.2.2. Without this the document is infinite, and TypeGenerator's
  # spread expansion loops forever rather than failing.
  describe "fragment spread cycles" do
    test "a fragment that spreads itself is rejected" do
      query = """
      query { user(id: "1") { ...F } }
      fragment F on User { name ...F }
      """

      assert [error] = errors(validate(query))
      assert error.message =~ ~s(fragment "F" spreads itself)
    end

    test "a cycle through another fragment is rejected" do
      query = """
      query { user(id: "1") { ...A } }
      fragment A on User { ...B }
      fragment B on User { ...A }
      """

      assert [_a, _b] = errors(validate(query))
    end

    test "a cycle that runs through a field is rejected" do
      query = """
      query { user(id: "1") { ...F } }
      fragment F on User { name posts { author { ...F } } }
      """

      assert [error] = errors(validate(query, types: types_with_author_cycle()))
      assert error.message =~ ~s(fragment "F" spreads itself)
    end

    test "a cycle that runs through an inline fragment is rejected" do
      query = """
      query { user(id: "1") { ...F } }
      fragment F on User { ... on User { ...F } }
      """

      assert [error] = errors(validate(query))
      assert error.message =~ ~s(fragment "F" spreads itself)
    end

    test "spreading the same fragment twice is not a cycle" do
      query = """
      query { user(id: "1") { ...F } }
      fragment F on User { ...G }
      fragment G on User { name }
      """

      assert errors(validate(query)) == []
    end
  end

  defp types_with_author_cycle do
    Map.merge(SchemaHelper.default_types(), %{
      "User" => %Type{
        kind: :object,
        name: "User",
        fields: %{
          "name" => %SchemaField{name: "name", type: %TypeRef{kind: :scalar, name: "String"}},
          "posts" => %SchemaField{name: "posts", type: %TypeRef{kind: :object, name: "Post"}}
        }
      },
      "Post" => %Type{
        kind: :object,
        name: "Post",
        fields: %{
          "author" => %SchemaField{name: "author", type: %TypeRef{kind: :object, name: "User"}}
        }
      }
    })
  end

  describe "unresolvable parent type" do
    test "inline fragment under a missing root type is skipped" do
      ctx = validate(~s|query { ... on User { name } }|, query_type: nil)
      assert errors(ctx) == []
    end

    test "inline fragment under a parent type absent from the schema is not applicable" do
      ctx =
        validate(~s|query { user(id: "1") { ... on User { name } } }|,
          types: types_with_dangling_field_type()
        )

      assert [error] = errors(ctx)
      assert error.message =~ "type \"User\" is not applicable to \"Ghost\""
    end
  end

  defp types_with_dangling_field_type do
    Map.merge(SchemaHelper.default_types(), %{
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields: %{
          "user" => %SchemaField{
            name: "user",
            type: %TypeRef{kind: :object, name: "Ghost"},
            args: %{}
          }
        }
      }
    })
  end

  defp parse!(query) do
    {:ok, doc} = TypedGql.Parser.parse(query)
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
              "id" => %TypedGql.Schema.InputValue{
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
              "id" => %TypedGql.Schema.InputValue{
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
