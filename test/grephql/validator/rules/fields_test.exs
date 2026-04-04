defmodule Grephql.Validator.Rules.FieldsTest do
  use ExUnit.Case, async: true

  alias Grephql.Schema.Field, as: SchemaField
  alias Grephql.Schema.Type
  alias Grephql.Schema.TypeRef
  alias Grephql.Test.SchemaHelper
  alias Grephql.Validator.Context
  alias Grephql.Validator.Rules.Fields

  describe "field existence" do
    test "valid fields pass" do
      ctx = validate("query { user { name email } }")
      assert errors(ctx) == []
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
  end

  describe "scalar sub-selection" do
    test "sub-selection on scalar fails" do
      ctx = validate("query { user { name { length } } }")
      assert [error] = errors(ctx)
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
      assert [error] = errors(ctx)
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

  defp parse!(query) do
    {:ok, doc} = Grephql.Parser.parse(query)
    doc
  end

  defp validate(query, schema_opts \\ []) do
    schema = SchemaHelper.build_schema(schema_opts)
    ctx = %Context{schema: schema}
    Fields.validate(parse!(query), ctx)
  end

  defp errors(ctx), do: Context.errors_by_severity(ctx, :error)
end
