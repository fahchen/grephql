defmodule TypedGql.Validator.Rules.FieldsTest do
  use ExUnit.Case, async: true

  alias TypedGql.Schema.Field, as: SchemaField
  alias TypedGql.Schema.Type
  alias TypedGql.Schema.TypeRef
  alias TypedGql.Test.SchemaHelper
  alias TypedGql.Validator.Context
  alias TypedGql.Validator.Rules.Fields

  describe "field existence" do
    test "valid fields pass" do
      ctx = validate("query { user { name email } }")
      assert errors(ctx) == []
    end

    # A condition-less inline fragment keeps its enclosing type, so its
    # selections are checked like any other. Dropping that type made the whole
    # block invisible to this rule.
    test "non-existent field inside a condition-less inline fragment fails" do
      ctx = validate("query { user { ... { nonExistentField } } }")
      assert [error] = errors(ctx)
      assert error.message =~ "\"nonExistentField\" does not exist on type \"User\""
    end

    test "non-existent field fails" do
      ctx = validate("query { user { nonExistentField } }")
      assert [error] = errors(ctx)
      assert error.message =~ "\"nonExistentField\" does not exist on type \"User\""
    end

    test "non-existent root field fails" do
      ctx = validate("query { unknownField { id } }")
      assert [error] = errors(ctx)
      assert error.message =~ "\"unknownField\" does not exist on type \"Query\""
    end

    test "__typename introspection field passes" do
      ctx = validate("query { user { __typename name } }")
      assert errors(ctx) == []
    end

    # A real introspection result lists __Schema and __Type among its types, so
    # the meta-fields resolve like any other.
    test "__type introspection field passes" do
      ctx = validate(~s|query { __type(name: "User") { name } }|, types: introspection_types())
      assert errors(ctx) == []
    end

    test "__schema introspection field passes" do
      ctx =
        validate("query { __schema { queryType { name } } }", types: introspection_types())

      assert errors(ctx) == []
    end
  end

  describe "input type as output field" do
    test "input object type used as output field type fails" do
      types =
        Map.merge(SchemaHelper.default_types(), %{
          "CreateUserInput" => %Type{kind: :input_object, name: "CreateUserInput"},
          "Query" => %Type{
            kind: :object,
            name: "Query",
            fields: %{
              "broken" => %SchemaField{
                name: "broken",
                type: %TypeRef{kind: :input_object, name: "CreateUserInput"}
              }
            }
          }
        })

      ctx = validate("query { broken }", types: types)
      assert [error] = errors(ctx)
      assert error.message =~ "input type cannot be used as an output field type"
    end
  end

  describe "scalar sub-selection" do
    test "sub-selection on scalar fails" do
      ctx = validate("query { user { name { length } } }")
      assert [error | _rest] = errors(ctx)
      assert error.message =~ "\"name\" is a scalar and cannot have sub-selections"
    end

    test "scalar without sub-selection passes" do
      ctx = validate("query { user { name } }")
      assert errors(ctx) == []
    end
  end

  describe "composite type sub-selection" do
    test "object type without sub-selection fails" do
      ctx = validate("query { user }")
      assert [error] = errors(ctx)
      assert error.message =~ "\"user\" is an object type and requires a sub-selection"
    end

    test "object type with sub-selection passes" do
      ctx = validate("query { user { name } }")
      assert errors(ctx) == []
    end
  end

  describe "enum type sub-selection" do
    test "sub-selection on enum field fails" do
      types =
        Map.merge(SchemaHelper.default_types(), %{
          "Role" => %Type{kind: :enum, name: "Role"},
          "User" => %Type{
            kind: :object,
            name: "User",
            fields: %{
              "role" => %SchemaField{
                name: "role",
                type: %TypeRef{kind: :enum, name: "Role"}
              },
              "name" => %SchemaField{
                name: "name",
                type: %TypeRef{kind: :scalar, name: "String"}
              }
            }
          }
        })

      ctx = validate("query { user { role { value } } }", types: types)
      assert [error | _rest] = errors(ctx)
      assert error.message =~ "\"role\" is an enum and cannot have sub-selections"
    end
  end

  describe "nested field validation" do
    test "validates fields recursively through object types" do
      types =
        Map.merge(SchemaHelper.default_types(), %{
          "User" => %Type{
            kind: :object,
            name: "User",
            fields: %{
              "name" => %SchemaField{
                name: "name",
                type: %TypeRef{kind: :scalar, name: "String"}
              },
              "posts" => %SchemaField{
                name: "posts",
                type: %TypeRef{
                  kind: :list,
                  of_type: %TypeRef{kind: :object, name: "Post"}
                }
              }
            }
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

      ctx = validate("query { user { posts { title } } }", types: types)
      assert errors(ctx) == []
    end

    test "catches invalid nested field" do
      types =
        Map.merge(SchemaHelper.default_types(), %{
          "User" => %Type{
            kind: :object,
            name: "User",
            fields: %{
              "name" => %SchemaField{
                name: "name",
                type: %TypeRef{kind: :scalar, name: "String"}
              },
              "posts" => %SchemaField{
                name: "posts",
                type: %TypeRef{
                  kind: :list,
                  of_type: %TypeRef{kind: :object, name: "Post"}
                }
              }
            }
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

      ctx = validate("query { user { posts { bogus } } }", types: types)
      assert [error] = errors(ctx)
      assert error.message =~ "\"bogus\" does not exist on type \"Post\""
    end
  end

  describe "list type unwrapping" do
    test "validates fields through NonNull > List > Object wrapping" do
      ctx = validate("query { users { name } }")
      assert errors(ctx) == []
    end
  end

  describe "dangling type reference" do
    test "field whose type is absent from the schema is reported" do
      types =
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

      assert [error] = errors(validate("query { user }", types: types))
      assert error.message == ~s(type "Ghost" of field "user" is not defined in the schema)
    end
  end

  defp introspection_types do
    Map.merge(SchemaHelper.default_types(), %{
      "__Schema" => %Type{
        kind: :object,
        name: "__Schema",
        fields: %{
          "queryType" => %SchemaField{
            name: "queryType",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :object, name: "__Type"}}
          }
        }
      },
      "__Type" => %Type{
        kind: :object,
        name: "__Type",
        fields: %{
          "name" => %SchemaField{name: "name", type: %TypeRef{kind: :scalar, name: "String"}}
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
    Fields.validate(parse!(query), ctx)
  end

  defp errors(ctx), do: Context.errors_by_severity(ctx, :error)
end
