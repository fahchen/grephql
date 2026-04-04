defmodule Grephql.Validator.Rules.InputObjectsTest do
  use ExUnit.Case, async: true

  alias Grephql.Schema.Field, as: SchemaField
  alias Grephql.Schema.InputValue
  alias Grephql.Schema.Type
  alias Grephql.Schema.TypeRef
  alias Grephql.Test.SchemaHelper
  alias Grephql.Validator.Context
  alias Grephql.Validator.Rules.InputObjects

  describe "input field existence" do
    test "valid input fields pass" do
      types = types_with_input()

      ctx =
        validate(~s|query { createUser(input: {name: "Alice", email: "a@b.c"}) { id } }|,
          types: types
        )

      assert errors(ctx) == []
    end

    test "unknown input field fails" do
      types = types_with_input()

      ctx =
        validate(~s|query { createUser(input: {name: "Alice", bogus: "x"}) { id } }|,
          types: types
        )

      assert [error] = errors(ctx)
      assert error.message =~ "field \"bogus\" is not defined on input type \"CreateUserInput\""
    end
  end

  describe "required input fields" do
    test "all required fields provided passes" do
      types = types_with_input()
      ctx = validate(~s|query { createUser(input: {name: "Alice"}) { id } }|, types: types)
      req_errors = Enum.filter(errors(ctx), &(&1.message =~ "required field"))
      assert req_errors == []
    end

    test "missing required field fails" do
      types = types_with_input()
      ctx = validate(~s|query { createUser(input: {email: "a@b.c"}) { id } }|, types: types)
      req_errors = Enum.filter(errors(ctx), &(&1.message =~ "required field"))
      assert [error] = req_errors

      assert error.message =~
               "required field \"name\" is missing on input type \"CreateUserInput\""
    end
  end

  describe "input field uniqueness" do
    test "duplicate input field fails" do
      types = types_with_input()

      ctx =
        validate(
          ~s|query { createUser(input: {name: "Alice", name: "Bob"}) { id } }|,
          types: types
        )

      dup_errors = Enum.filter(errors(ctx), &(&1.message =~ "duplicate field"))
      assert [error] = dup_errors
      assert error.message =~ "duplicate field \"name\" in input object"
    end
  end

  describe "nested input objects" do
    test "valid nested input passes" do
      types = types_with_nested_input()

      ctx =
        validate(
          ~s|query { createUser(input: {name: "Alice", address: {city: "NY"}}) { id } }|,
          types: types
        )

      assert errors(ctx) == []
    end

    test "invalid nested field fails" do
      types = types_with_nested_input()

      ctx =
        validate(
          ~s|query { createUser(input: {name: "Alice", address: {bogus: "x"}}) { id } }|,
          types: types
        )

      nested_errors = Enum.filter(errors(ctx), &(&1.message =~ "bogus"))
      assert [error] = nested_errors
      assert error.message =~ "field \"bogus\" is not defined on input type \"AddressInput\""
    end
  end

  describe "list of input objects" do
    test "valid list of inputs passes" do
      types = types_with_list_input()

      ctx =
        validate(
          ~s|query { createUsers(inputs: [{name: "Alice"}, {name: "Bob"}]) { id } }|,
          types: types
        )

      assert errors(ctx) == []
    end

    test "invalid field in list item fails" do
      types = types_with_list_input()

      ctx =
        validate(
          ~s|query { createUsers(inputs: [{name: "Alice"}, {bogus: "x"}]) { id } }|,
          types: types
        )

      assert [_error | _rest] = Enum.filter(errors(ctx), &(&1.message =~ "bogus"))
    end
  end

  describe "non-input-object values" do
    test "scalar argument value is not checked" do
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
    InputObjects.validate(parse!(query), ctx)
  end

  defp errors(ctx), do: Context.errors_by_severity(ctx, :error)

  defp types_with_input do
    Map.merge(SchemaHelper.default_types(), %{
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields:
          Map.merge(SchemaHelper.default_types()["Query"].fields, %{
            "createUser" => %SchemaField{
              name: "createUser",
              type: %TypeRef{kind: :object, name: "User"},
              args: %{
                "input" => %InputValue{
                  name: "input",
                  type: %TypeRef{
                    kind: :non_null,
                    of_type: %TypeRef{kind: :input_object, name: "CreateUserInput"}
                  }
                }
              }
            }
          })
      },
      "CreateUserInput" => %Type{
        kind: :input_object,
        name: "CreateUserInput",
        input_fields: %{
          "name" => %InputValue{
            name: "name",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "String"}}
          },
          "email" => %InputValue{
            name: "email",
            type: %TypeRef{kind: :scalar, name: "String"}
          }
        }
      }
    })
  end

  defp types_with_nested_input do
    Map.merge(types_with_input(), %{
      "CreateUserInput" => %Type{
        kind: :input_object,
        name: "CreateUserInput",
        input_fields: %{
          "name" => %InputValue{
            name: "name",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "String"}}
          },
          "address" => %InputValue{
            name: "address",
            type: %TypeRef{kind: :input_object, name: "AddressInput"}
          }
        }
      },
      "AddressInput" => %Type{
        kind: :input_object,
        name: "AddressInput",
        input_fields: %{
          "city" => %InputValue{
            name: "city",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "String"}}
          }
        }
      }
    })
  end

  defp types_with_list_input do
    Map.merge(types_with_input(), %{
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields:
          Map.merge(SchemaHelper.default_types()["Query"].fields, %{
            "createUsers" => %SchemaField{
              name: "createUsers",
              type: %TypeRef{kind: :list, of_type: %TypeRef{kind: :object, name: "User"}},
              args: %{
                "inputs" => %InputValue{
                  name: "inputs",
                  type: %TypeRef{
                    kind: :non_null,
                    of_type: %TypeRef{
                      kind: :list,
                      of_type: %TypeRef{kind: :input_object, name: "CreateUserInput"}
                    }
                  }
                }
              }
            }
          })
      }
    })
  end
end
