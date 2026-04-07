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

  describe "deprecated argument detection" do
    test "non-deprecated argument produces no warning" do
      types = types_with_deprecated_arg()
      ctx = validate(~s|query { user(id: "1") { name } }|, types: types)
      assert warnings(ctx) == []
    end

    test "deprecated argument produces warning" do
      types = types_with_deprecated_arg()
      ctx = validate(~s|query { user(id: "1", legacyId: "old") { name } }|, types: types)
      assert [warning] = warnings(ctx)
      assert warning.message =~ "argument \"legacyId\" is deprecated: use id instead"
    end

    test "deprecated argument without reason" do
      types = types_with_deprecated_arg_no_reason()
      ctx = validate(~s|query { user(id: "1", legacyId: "old") { name } }|, types: types)
      assert [warning] = warnings(ctx)
      assert warning.message == "argument \"legacyId\" is deprecated"
    end
  end

  describe "deprecated input object field detection" do
    test "non-deprecated input field produces no warning" do
      types = types_with_deprecated_input_field()

      ctx =
        validate(
          ~s|mutation { createUser(input: {name: "Alice"}) { id } }|,
          types: types,
          mutation_type: "Mutation"
        )

      assert warnings(ctx) == []
    end

    test "deprecated input field produces warning" do
      types = types_with_deprecated_input_field()

      ctx =
        validate(
          ~s|mutation { createUser(input: {name: "Alice", nickname: "Ali"}) { id } }|,
          types: types,
          mutation_type: "Mutation"
        )

      assert [warning] = warnings(ctx)

      assert warning.message =~
               "input field \"nickname\" on \"CreateUserInput\" is deprecated: use displayName"
    end

    test "deprecated nested input field produces warning" do
      types = types_with_deprecated_nested_input_field()

      ctx =
        validate(
          ~s|mutation { createUser(input: {name: "Alice", profile: {bio: "hi", oldAvatar: "url"}}) { id } }|,
          types: types,
          mutation_type: "Mutation"
        )

      assert [warning] = warnings(ctx)

      assert warning.message =~
               "input field \"oldAvatar\" on \"ProfileInput\" is deprecated: use avatarUrl"
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

  defp types_with_deprecated_arg do
    Map.merge(SchemaHelper.default_types(), %{
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields: %{
          "user" => %SchemaField{
            name: "user",
            type: %TypeRef{kind: :object, name: "User"},
            args: %{
              "id" => %InputValue{
                name: "id",
                type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
              },
              "legacyId" => %InputValue{
                name: "legacyId",
                type: %TypeRef{kind: :scalar, name: "String"},
                is_deprecated: true,
                deprecation_reason: "use id instead"
              }
            }
          }
        }
      }
    })
  end

  defp types_with_deprecated_arg_no_reason do
    Map.merge(SchemaHelper.default_types(), %{
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields: %{
          "user" => %SchemaField{
            name: "user",
            type: %TypeRef{kind: :object, name: "User"},
            args: %{
              "id" => %InputValue{
                name: "id",
                type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "ID"}}
              },
              "legacyId" => %InputValue{
                name: "legacyId",
                type: %TypeRef{kind: :scalar, name: "String"},
                is_deprecated: true
              }
            }
          }
        }
      }
    })
  end

  defp types_with_deprecated_input_field do
    Map.merge(SchemaHelper.default_types(), %{
      "Query" => %Type{
        kind: :object,
        name: "Query",
        fields: %{
          "user" => SchemaHelper.default_types()["Query"].fields["user"]
        }
      },
      "Mutation" => %Type{
        kind: :object,
        name: "Mutation",
        fields: %{
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
        }
      },
      "CreateUserInput" => %Type{
        kind: :input_object,
        name: "CreateUserInput",
        input_fields: %{
          "name" => %InputValue{
            name: "name",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "String"}}
          },
          "nickname" => %InputValue{
            name: "nickname",
            type: %TypeRef{kind: :scalar, name: "String"},
            is_deprecated: true,
            deprecation_reason: "use displayName"
          }
        }
      }
    })
  end

  defp types_with_deprecated_nested_input_field do
    base = types_with_deprecated_input_field()

    Map.merge(base, %{
      "CreateUserInput" => %Type{
        kind: :input_object,
        name: "CreateUserInput",
        input_fields: %{
          "name" => %InputValue{
            name: "name",
            type: %TypeRef{kind: :non_null, of_type: %TypeRef{kind: :scalar, name: "String"}}
          },
          "profile" => %InputValue{
            name: "profile",
            type: %TypeRef{kind: :input_object, name: "ProfileInput"}
          }
        }
      },
      "ProfileInput" => %Type{
        kind: :input_object,
        name: "ProfileInput",
        input_fields: %{
          "bio" => %InputValue{
            name: "bio",
            type: %TypeRef{kind: :scalar, name: "String"}
          },
          "oldAvatar" => %InputValue{
            name: "oldAvatar",
            type: %TypeRef{kind: :scalar, name: "String"},
            is_deprecated: true,
            deprecation_reason: "use avatarUrl"
          }
        }
      }
    })
  end

  describe "deprecated enum value in list argument" do
    test "deprecated enum value in list produces warning" do
      types = types_with_deprecated_enum_list()
      ctx = validate("query { usersByRoles(roles: [ADMIN, GUEST]) { name } }", types: types)
      assert [warning] = warnings(ctx)
      assert warning.message =~ "enum value \"GUEST\" is deprecated: no longer supported"
    end

    test "non-deprecated enum values in list produce no warning" do
      types = types_with_deprecated_enum_list()
      ctx = validate("query { usersByRoles(roles: [ADMIN, USER]) { name } }", types: types)
      assert warnings(ctx) == []
    end
  end

  describe "deprecation reason formatting" do
    test "empty string deprecation reason omits suffix" do
      types = types_with_deprecated_field_empty_reason()
      ctx = validate(~s|query { user(id: "1") { email } }|, types: types)
      assert [warning] = warnings(ctx)
      assert warning.message == "field \"email\" on \"User\" is deprecated"
    end
  end

  defp types_with_deprecated_field_empty_reason do
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
            deprecation_reason: ""
          }
        }
      }
    })
  end

  defp types_with_deprecated_enum_list do
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
