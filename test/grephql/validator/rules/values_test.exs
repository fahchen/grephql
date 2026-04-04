defmodule Grephql.Validator.Rules.ValuesTest do
  use ExUnit.Case, async: true

  alias Grephql.Schema.EnumValue, as: SchemaEnumValue
  alias Grephql.Schema.Field, as: SchemaField
  alias Grephql.Schema.InputValue
  alias Grephql.Schema.Type
  alias Grephql.Schema.TypeRef
  alias Grephql.Test.SchemaHelper
  alias Grephql.Validator.Context
  alias Grephql.Validator.Rules.Values

  describe "enum value validation" do
    test "valid enum value passes" do
      types = types_with_enum()
      ctx = validate("query { usersByRole(role: ADMIN) { name } }", types: types)
      assert errors(ctx) == []
    end

    test "invalid enum value fails" do
      types = types_with_enum()
      ctx = validate("query { usersByRole(role: SUPERADMIN) { name } }", types: types)
      assert [error] = errors(ctx)
      assert error.message =~ "enum value \"SUPERADMIN\" is not valid for type \"Role\""
    end

    test "enum value for non-null enum passes" do
      types = types_with_non_null_enum()
      ctx = validate("query { usersByRole(role: ADMIN) { name } }", types: types)
      assert errors(ctx) == []
    end
  end

  describe "non-enum values" do
    test "string argument is not checked as enum" do
      ctx = validate(~s|query { user(id: "1") { name } }|)
      assert errors(ctx) == []
    end

    test "variable is not checked" do
      types = types_with_enum()
      ctx = validate("query($role: Role!) { usersByRole(role: $role) { name } }", types: types)
      assert errors(ctx) == []
    end
  end

  describe "enum in list" do
    test "valid enum values in list pass" do
      types = types_with_enum_list()
      ctx = validate("query { usersByRoles(roles: [ADMIN, USER]) { name } }", types: types)
      assert errors(ctx) == []
    end

    test "invalid enum value in list fails" do
      types = types_with_enum_list()
      ctx = validate("query { usersByRoles(roles: [ADMIN, BOGUS]) { name } }", types: types)
      assert [error] = errors(ctx)
      assert error.message =~ "enum value \"BOGUS\" is not valid for type \"Role\""
    end
  end

  defp parse!(query) do
    {:ok, doc} = Grephql.Parser.parse(query)
    doc
  end

  defp validate(query, schema_opts \\ []) do
    schema = SchemaHelper.build_schema(schema_opts)
    ctx = %Context{schema: schema}
    Values.validate(parse!(query), ctx)
  end

  defp errors(ctx), do: Context.errors_by_severity(ctx, :error)

  defp role_type do
    %Type{
      kind: :enum,
      name: "Role",
      enum_values: [
        %SchemaEnumValue{name: "ADMIN"},
        %SchemaEnumValue{name: "USER"},
        %SchemaEnumValue{name: "GUEST"}
      ]
    }
  end

  defp types_with_enum do
    Map.merge(SchemaHelper.default_types(), %{
      "Role" => role_type(),
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields:
          Map.merge(SchemaHelper.default_types()["Query"].fields, %{
            "usersByRole" => %SchemaField{
              name: "usersByRole",
              type: %TypeRef{kind: :list, of_type: %TypeRef{kind: :object, name: "User"}},
              args: %{
                "role" => %InputValue{
                  name: "role",
                  type: %TypeRef{kind: :enum, name: "Role"}
                }
              }
            }
          })
      }
    })
  end

  defp types_with_non_null_enum do
    base = types_with_enum()

    put_in(base["Query"].fields["usersByRole"].args["role"].type, %TypeRef{
      kind: :non_null,
      of_type: %TypeRef{kind: :enum, name: "Role"}
    })
  end

  defp types_with_enum_list do
    Map.merge(SchemaHelper.default_types(), %{
      "Role" => role_type(),
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields:
          Map.merge(SchemaHelper.default_types()["Query"].fields, %{
            "usersByRoles" => %SchemaField{
              name: "usersByRoles",
              type: %TypeRef{kind: :list, of_type: %TypeRef{kind: :object, name: "User"}},
              args: %{
                "roles" => %InputValue{
                  name: "roles",
                  type: %TypeRef{
                    kind: :list,
                    of_type: %TypeRef{kind: :enum, name: "Role"}
                  }
                }
              }
            }
          })
      }
    })
  end
end
