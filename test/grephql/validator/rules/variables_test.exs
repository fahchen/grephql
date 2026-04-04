defmodule Grephql.Validator.Rules.VariablesTest do
  use ExUnit.Case, async: true

  alias Grephql.Schema.Field, as: SchemaField
  alias Grephql.Schema.InputValue
  alias Grephql.Schema.Type
  alias Grephql.Schema.TypeRef
  alias Grephql.Test.SchemaHelper
  alias Grephql.Validator.Context
  alias Grephql.Validator.Rules.Variables

  describe "unique variable definitions" do
    test "unique variables pass" do
      ctx = validate("query($a: ID!) { user(id: $a) { name } }")
      assert errors(ctx) == []
    end

    test "duplicate variable fails" do
      ctx = validate("query($id: ID!, $id: String) { user(id: $id) { name } }")
      duplicate_errors = Enum.filter(errors(ctx), &(&1.message =~ "duplicate variable"))
      assert [error] = duplicate_errors
      assert error.message =~ "duplicate variable \"$id\""
    end
  end

  describe "unused variables" do
    test "all variables used passes" do
      ctx = validate("query($id: ID!) { user(id: $id) { name } }")
      assert errors(ctx) == []
    end

    test "unused variable fails" do
      ctx = validate("query($id: ID!, $unused: String) { user(id: $id) { name } }")
      assert [error] = errors(ctx)
      assert error.message =~ "variable \"$unused\" is defined but not used"
    end
  end

  describe "undefined variables" do
    test "defined variable passes" do
      ctx = validate("query($id: ID!) { user(id: $id) { name } }")
      assert errors(ctx) == []
    end

    test "undefined variable fails" do
      ctx = validate("query { user(id: $id) { name } }")
      assert [error] = errors(ctx)
      assert error.message =~ "variable \"$id\" is used but not defined"
    end
  end

  describe "variable type compatibility" do
    test "matching non-null type passes" do
      ctx = validate("query($id: ID!) { user(id: $id) { name } }")
      assert type_errors(ctx) == []
    end

    test "non-null variable for nullable argument passes" do
      types = types_with_nullable_id_arg()
      ctx = validate("query($id: ID!) { user(id: $id) { name } }", types: types)
      assert type_errors(ctx) == []
    end

    test "nullable variable for non-null argument fails" do
      ctx = validate("query($id: ID) { user(id: $id) { name } }")
      assert [error] = type_errors(ctx)

      assert error.message =~
               "variable \"$id\" of type \"ID\" is not compatible with argument \"id\" of type \"ID!\""
    end

    test "list type matching passes" do
      types = types_with_list_arg()
      ctx = validate("query($ids: [ID!]!) { usersByIds(ids: $ids) { name } }", types: types)
      assert type_errors(ctx) == []
    end

    test "mismatched named type fails" do
      ctx = validate("query($id: String!) { user(id: $id) { name } }")
      assert [error] = type_errors(ctx)

      assert error.message =~
               "variable \"$id\" of type \"String!\" is not compatible with argument \"id\" of type \"ID!\""
    end

    test "undefined variable skips type check" do
      ctx = validate("query { user(id: $id) { name } }")
      assert type_errors(ctx) == []
    end
  end

  describe "operation without variables" do
    test "operation with no variable definitions passes" do
      ctx = validate(~s|query { user(id: "1") { name } }|)
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
    Variables.validate(parse!(query), ctx)
  end

  defp errors(ctx), do: Context.errors_by_severity(ctx, :error)

  defp type_errors(ctx) do
    Enum.filter(errors(ctx), &(&1.message =~ "is not compatible with"))
  end

  defp types_with_nullable_id_arg do
    Map.merge(SchemaHelper.default_types(), %{
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields: %{
          "user" => %SchemaField{
            name: "user",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :object, name: "User"}},
            args: %{
              "id" => %InputValue{
                name: "id",
                type: %TypeRef{kind: :scalar, name: "ID"}
              }
            }
          }
        }
      }
    })
  end

  defp types_with_list_arg do
    Map.merge(SchemaHelper.default_types(), %{
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields: %{
          "user" => %SchemaField{
            name: "user",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :object, name: "User"}},
            args: %{
              "id" => %InputValue{
                name: "id",
                type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
              }
            }
          },
          "usersByIds" => %SchemaField{
            name: "usersByIds",
            type: %TypeRef{kind: :list, of_type: %TypeRef{kind: :object, name: "User"}},
            args: %{
              "ids" => %InputValue{
                name: "ids",
                type: %TypeRef{
                  kind: :non_null,
                  of_type: %TypeRef{
                    kind: :list,
                    of_type: %TypeRef{
                      kind: :non_null,
                      of_type: %TypeRef{kind: :scalar, name: "ID"}
                    }
                  }
                }
              }
            }
          }
        }
      }
    })
  end
end
