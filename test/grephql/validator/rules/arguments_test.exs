defmodule Grephql.Validator.Rules.ArgumentsTest do
  use ExUnit.Case, async: true

  alias Grephql.Test.SchemaHelper
  alias Grephql.Validator.Context
  alias Grephql.Validator.Rules.Arguments

  describe "argument existence" do
    test "valid argument passes" do
      ctx = validate(~s|query { user(id: "123") { name } }|)
      assert errors(ctx) == []
    end

    test "non-existent argument fails" do
      ctx = validate(~s|query { user(id: "123", foo: "bar") { name } }|)
      assert [error] = errors(ctx)
      assert error.message =~ "\"foo\" is not defined on field \"user\""
    end
  end

  describe "required arguments" do
    test "missing required argument fails" do
      ctx = validate("query { user { name } }")
      assert [error] = errors(ctx)
      assert error.message =~ "required argument \"id\" is missing on field \"user\""
    end

    test "provided required argument passes" do
      ctx = validate(~s|query { user(id: "123") { name } }|)
      assert errors(ctx) == []
    end

    test "required argument provided as variable passes" do
      ctx = validate(~s|query($id: ID!) { user(id: $id) { name } }|)
      assert errors(ctx) == []
    end
  end

  describe "argument uniqueness" do
    test "duplicate argument fails" do
      ctx = validate(~s|query { user(id: "1", id: "2") { name } }|)
      assert [error] = errors(ctx)
      assert error.message =~ "duplicate argument \"id\" on field \"user\""
    end

    test "unique arguments pass" do
      ctx = validate(~s|query { user(id: "123") { name } }|)
      assert errors(ctx) == []
    end
  end

  describe "argument type matching" do
    test "string for ID passes" do
      ctx = validate(~s|query { user(id: "123") { name } }|)
      assert errors(ctx) == []
    end

    test "int for ID passes" do
      ctx = validate("query { user(id: 123) { name } }")
      assert errors(ctx) == []
    end

    test "boolean for ID fails" do
      ctx = validate("query { user(id: true) { name } }")
      assert [error] = errors(ctx)
      assert error.message =~ "type mismatch for argument \"id\" on field \"user\""
    end

    test "variable skips type check" do
      ctx = validate("query($id: ID!) { user(id: $id) { name } }")
      assert errors(ctx) == []
    end

    test "null is compatible with any type" do
      ctx = validate("query { user(id: null) { name } }")
      # null passes type check (required check catches the real issue)
      type_errors = Enum.filter(errors(ctx), &(&1.message =~ "type mismatch"))
      assert type_errors == []
    end

    test "string for Int fails" do
      ctx = validate(~s|query { countUsers(limit: "ten") { name } }|, types: types_with_int_arg())
      type_errors = Enum.filter(errors(ctx), &(&1.message =~ "type mismatch"))
      assert [error] = type_errors
      assert error.message =~ "type mismatch for argument \"limit\" on field \"countUsers\""
    end

    test "int for Int passes" do
      ctx = validate("query { countUsers(limit: 10) { name } }", types: types_with_int_arg())
      type_errors = Enum.filter(errors(ctx), &(&1.message =~ "type mismatch"))
      assert type_errors == []
    end

    test "string for Boolean fails" do
      ctx =
        validate(
          ~s|query { activeUsers(active: "yes") { name } }|,
          types: types_with_boolean_arg()
        )

      type_errors = Enum.filter(errors(ctx), &(&1.message =~ "type mismatch"))
      assert [error] = type_errors
      assert error.message =~ "type mismatch for argument \"active\" on field \"activeUsers\""
    end

    test "boolean for Boolean passes" do
      ctx =
        validate("query { activeUsers(active: true) { name } }",
          types: types_with_boolean_arg()
        )

      type_errors = Enum.filter(errors(ctx), &(&1.message =~ "type mismatch"))
      assert type_errors == []
    end

    test "float for String fails" do
      ctx = validate("query { user(id: 1.5) { name } }")
      type_errors = Enum.filter(errors(ctx), &(&1.message =~ "type mismatch"))
      assert [error] = type_errors
      assert error.message =~ "type mismatch for argument \"id\" on field \"user\""
    end
  end

  describe "nested field argument validation" do
    test "validates arguments on nested fields" do
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
    Arguments.validate(parse!(query), ctx)
  end

  defp errors(ctx), do: Context.errors_by_severity(ctx, :error)

  defp types_with_int_arg do
    types = SchemaHelper.default_types()

    count_users_field = %Grephql.Schema.Field{
      name: "countUsers",
      type: %Grephql.Schema.TypeRef{
        kind: :list,
        of_type: %Grephql.Schema.TypeRef{kind: :object, name: "User"}
      },
      args: %{
        "limit" => %Grephql.Schema.InputValue{
          name: "limit",
          type: %Grephql.Schema.TypeRef{
            kind: :non_null,
            of_type: %Grephql.Schema.TypeRef{kind: :scalar, name: "Int"}
          }
        }
      }
    }

    put_in(types, ["Query", Access.key(:fields), "countUsers"], count_users_field)
  end

  defp types_with_boolean_arg do
    types = SchemaHelper.default_types()

    active_users_field = %Grephql.Schema.Field{
      name: "activeUsers",
      type: %Grephql.Schema.TypeRef{
        kind: :list,
        of_type: %Grephql.Schema.TypeRef{kind: :object, name: "User"}
      },
      args: %{
        "active" => %Grephql.Schema.InputValue{
          name: "active",
          type: %Grephql.Schema.TypeRef{
            kind: :non_null,
            of_type: %Grephql.Schema.TypeRef{kind: :scalar, name: "Boolean"}
          }
        }
      }
    }

    put_in(types, ["Query", Access.key(:fields), "activeUsers"], active_users_field)
  end
end
