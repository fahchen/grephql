defmodule Grephql.Validator.Rules.DeprecationTest do
  use ExUnit.Case, async: true

  alias Grephql.Schema.EnumValue, as: SchemaEnumValue
  alias Grephql.Schema.Field, as: SchemaField
  alias Grephql.Schema.InputValue
  alias Grephql.Schema.Type
  alias Grephql.Schema.TypeRef
  alias Grephql.Test.SchemaHelper
  alias Grephql.Validator.Context
  alias Grephql.Validator.Rules.Deprecation

  describe "deprecated field detection" do
    test "non-deprecated field produces no warning" do
      ctx = validate(~s|query { user(id: "1") { name } }|)
      assert warnings(ctx) == []
    end

    test "deprecated field produces warning" do
      types = types_with_deprecated_field()
      ctx = validate(~s|query { user(id: "1") { email } }|, types: types)
      assert [warning] = warnings(ctx)

      assert warning.message =~
               "field \"email\" on \"User\" is deprecated: use contactEmail instead"
    end

    test "deprecated field without reason" do
      types = types_with_deprecated_field_no_reason()
      ctx = validate(~s|query { user(id: "1") { email } }|, types: types)
      assert [warning] = warnings(ctx)
      assert warning.message == "field \"email\" on \"User\" is deprecated"
    end
  end

  describe "deprecated enum value detection" do
    test "non-deprecated enum value produces no warning" do
      types = types_with_deprecated_enum()
      ctx = validate("query { usersByRole(role: ADMIN) { name } }", types: types)
      assert warnings(ctx) == []
    end

    test "deprecated enum value produces warning" do
      types = types_with_deprecated_enum()
      ctx = validate("query { usersByRole(role: GUEST) { name } }", types: types)
      assert [warning] = warnings(ctx)
      assert warning.message =~ "enum value \"GUEST\" is deprecated: no longer supported"
    end
  end

  defp parse!(query) do
    {:ok, doc} = Grephql.Parser.parse(query)
    doc
  end

  defp validate(query, schema_opts \\ []) do
    schema = SchemaHelper.build_schema(schema_opts)
    ctx = %Context{schema: schema}
    Deprecation.validate(parse!(query), ctx)
  end

  defp warnings(ctx), do: Context.errors_by_severity(ctx, :warning)

  defp types_with_deprecated_field do
    Map.merge(SchemaHelper.default_types(), %{
      "User" => %Type{
        kind: :object,
        name: "User",
        fields: %{
          "id" => %SchemaField{
            name: "id",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
          },
          "name" => %SchemaField{
            name: "name",
            type: %TypeRef{kind: :scalar, name: "String"}
          },
          "email" => %SchemaField{
            name: "email",
            type: %TypeRef{kind: :scalar, name: "String"},
            is_deprecated: true,
            deprecation_reason: "use contactEmail instead"
          }
        }
      }
    })
  end

  defp types_with_deprecated_field_no_reason do
    Map.merge(SchemaHelper.default_types(), %{
      "User" => %Type{
        kind: :object,
        name: "User",
        fields: %{
          "id" => %SchemaField{
            name: "id",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
          },
          "name" => %SchemaField{
            name: "name",
            type: %TypeRef{kind: :scalar, name: "String"}
          },
          "email" => %SchemaField{
            name: "email",
            type: %TypeRef{kind: :scalar, name: "String"},
            is_deprecated: true
          }
        }
      }
    })
  end

  defp types_with_deprecated_enum do
    Map.merge(SchemaHelper.default_types(), %{
      "Role" => %Type{
        kind: :enum,
        name: "Role",
        enum_values: [
          %SchemaEnumValue{name: "ADMIN"},
          %SchemaEnumValue{name: "USER"},
          %SchemaEnumValue{
            name: "GUEST",
            is_deprecated: true,
            deprecation_reason: "no longer supported"
          }
        ]
      },
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
end
