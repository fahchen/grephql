defmodule TypedGql.Validator.Rules.VariablesTest do
  use ExUnit.Case, async: true

  alias TypedGql.Schema.Directive, as: SchemaDirective
  alias TypedGql.Schema.Field, as: SchemaField
  alias TypedGql.Schema.InputValue
  alias TypedGql.Schema.Type
  alias TypedGql.Schema.TypeRef
  alias TypedGql.Test.SchemaHelper
  alias TypedGql.Validator.Context
  alias TypedGql.Validator.Rules.Variables

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

    test "variable used in directive argument passes" do
      ctx =
        validate(
          "query($showEmail: Boolean!) { user(id: \"1\") { email @include(if: $showEmail) } }",
          directives: [include_directive()]
        )

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

    test "directive argument variable type mismatch fails" do
      ctx =
        validate(
          "query($showEmail: String!) { user(id: \"1\") { email @include(if: $showEmail) } }",
          directives: [include_directive()]
        )

      assert [error] = type_errors(ctx)

      assert error.message =~
               "variable \"$showEmail\" of type \"String!\" is not compatible with argument \"if\" of type \"Boolean!\""
    end

    test "undefined variable skips type check" do
      ctx = validate("query { user(id: $id) { name } }")
      assert type_errors(ctx) == []
    end

    test "a mismatch inside a condition-less inline fragment is still reported" do
      ctx = validate("query($id: String) { ... { user(id: $id) { name } } }")
      assert [error] = type_errors(ctx)

      assert error.message =~
               "variable \"$id\" of type \"String\" is not compatible with argument \"id\" of type \"ID!\""
    end
  end

  describe "operation without variables" do
    test "operation with no variable definitions passes" do
      ctx = validate(~s|query { user(id: "1") { name } }|)
      assert errors(ctx) == []
    end
  end

  describe "selections without a resolvable type" do
    test "unknown field skips argument type checks" do
      ctx = validate(~s|query($id: ID!) { bogus(id: $id) }|)
      assert type_errors(ctx) == []
    end

    test "missing root type skips argument type checks" do
      ctx = validate(~s|query($id: ID!) { user(id: $id) { name } }|, query_type: nil)
      assert type_errors(ctx) == []
    end
  end

  describe "fragment selections" do
    test "inline fragment directive argument is type checked" do
      ctx =
        validate(
          ~s|query($showEmail: String!) { user(id: "1") { ... on User @include(if: $showEmail) { email } } }|,
          directives: [include_directive()]
        )

      assert [error] = type_errors(ctx)
      assert error.message =~ "variable \"$showEmail\" of type \"String!\""
    end

    test "fragment spread directive argument is type checked" do
      query = """
      query($showEmail: String!) { user(id: "1") { ...UserFields @include(if: $showEmail) } }
      fragment UserFields on User { email }
      """

      ctx = validate(query, directives: [include_directive()])

      assert [error] = type_errors(ctx)
      assert error.message =~ "variable \"$showEmail\" of type \"String!\""
    end
  end

  describe "type rendering" do
    test "unknown directive skips argument type checks" do
      ctx = validate(~s|query($flag: Boolean!) { user(id: "1") { name @nope(if: $flag) } }|)
      assert type_errors(ctx) == []
    end

    test "list variable type is rendered with brackets" do
      ctx = validate(~s|query($ids: [ID]) { user(id: $ids) { name } }|)
      assert [error] = type_errors(ctx)
      assert error.message =~ "of type \"[ID]\""
    end

    test "list argument type is rendered with brackets" do
      ctx =
        validate(~s|query($id: ID!) { usersByIds(ids: $id) { name } }|,
          types: types_with_list_arg()
        )

      assert [error] = type_errors(ctx)
      assert error.message =~ "argument \"ids\" of type \"[ID!]!\""
    end
  end

  defp parse!(query) do
    {:ok, doc} = TypedGql.Parser.parse(query)
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

  defp include_directive do
    %SchemaDirective{
      name: "include",
      locations: [:field, :fragment_spread, :inline_fragment],
      args: %{
        "if" => %InputValue{
          name: "if",
          type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "Boolean"}}
        }
      }
    }
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
