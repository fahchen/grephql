defmodule Grephql.Schema.ParserTest do
  use ExUnit.Case, async: true

  alias Grephql.Schema
  alias Grephql.Schema.Parser

  @introspection_json Jason.encode!(%{
                        "data" => %{
                          "__schema" => %{
                            "queryType" => %{"name" => "Query"},
                            "mutationType" => %{"name" => "Mutation"},
                            "subscriptionType" => nil,
                            "types" => [
                              %{
                                "kind" => "OBJECT",
                                "name" => "Query",
                                "description" => "Root query type",
                                "fields" => [
                                  %{
                                    "name" => "user",
                                    "description" => "Fetch a user by ID",
                                    "type" => %{
                                      "kind" => "NON_NULL",
                                      "name" => nil,
                                      "ofType" => %{
                                        "kind" => "OBJECT",
                                        "name" => "User",
                                        "ofType" => nil
                                      }
                                    },
                                    "args" => [
                                      %{
                                        "name" => "id",
                                        "description" => "User ID",
                                        "type" => %{
                                          "kind" => "NON_NULL",
                                          "name" => nil,
                                          "ofType" => %{
                                            "kind" => "SCALAR",
                                            "name" => "ID",
                                            "ofType" => nil
                                          }
                                        },
                                        "defaultValue" => nil
                                      }
                                    ],
                                    "isDeprecated" => false,
                                    "deprecationReason" => nil
                                  }
                                ],
                                "inputFields" => nil,
                                "interfaces" => [%{"name" => "Node"}],
                                "enumValues" => nil,
                                "possibleTypes" => nil
                              },
                              %{
                                "kind" => "OBJECT",
                                "name" => "User",
                                "description" => "A user",
                                "fields" => [
                                  %{
                                    "name" => "name",
                                    "description" => nil,
                                    "type" => %{
                                      "kind" => "SCALAR",
                                      "name" => "String",
                                      "ofType" => nil
                                    },
                                    "args" => [],
                                    "isDeprecated" => false,
                                    "deprecationReason" => nil
                                  },
                                  %{
                                    "name" => "email",
                                    "description" => nil,
                                    "type" => %{
                                      "kind" => "SCALAR",
                                      "name" => "String",
                                      "ofType" => nil
                                    },
                                    "args" => [],
                                    "isDeprecated" => true,
                                    "deprecationReason" => "Use emailAddress instead"
                                  }
                                ],
                                "inputFields" => nil,
                                "interfaces" => [],
                                "enumValues" => nil,
                                "possibleTypes" => nil
                              },
                              %{
                                "kind" => "SCALAR",
                                "name" => "ID",
                                "description" => "Built-in ID",
                                "fields" => nil,
                                "inputFields" => nil,
                                "interfaces" => nil,
                                "enumValues" => nil,
                                "possibleTypes" => nil
                              },
                              %{
                                "kind" => "ENUM",
                                "name" => "Role",
                                "description" => "User role",
                                "fields" => nil,
                                "inputFields" => nil,
                                "interfaces" => nil,
                                "enumValues" => [
                                  %{
                                    "name" => "ADMIN",
                                    "description" => "Administrator",
                                    "isDeprecated" => false,
                                    "deprecationReason" => nil
                                  },
                                  %{
                                    "name" => "USER",
                                    "description" => "Regular user",
                                    "isDeprecated" => false,
                                    "deprecationReason" => nil
                                  }
                                ],
                                "possibleTypes" => nil
                              },
                              %{
                                "kind" => "INPUT_OBJECT",
                                "name" => "CreateUserInput",
                                "description" => "Input for creating a user",
                                "fields" => nil,
                                "inputFields" => [
                                  %{
                                    "name" => "name",
                                    "description" => nil,
                                    "type" => %{
                                      "kind" => "NON_NULL",
                                      "name" => nil,
                                      "ofType" => %{
                                        "kind" => "SCALAR",
                                        "name" => "String",
                                        "ofType" => nil
                                      }
                                    },
                                    "defaultValue" => nil
                                  },
                                  %{
                                    "name" => "role",
                                    "description" => nil,
                                    "type" => %{
                                      "kind" => "ENUM",
                                      "name" => "Role",
                                      "ofType" => nil
                                    },
                                    "defaultValue" => "\"USER\""
                                  }
                                ],
                                "interfaces" => nil,
                                "enumValues" => nil,
                                "possibleTypes" => nil
                              }
                            ],
                            "directives" => [
                              %{
                                "name" => "skip",
                                "description" => "Skip this field",
                                "locations" => ["FIELD", "FRAGMENT_SPREAD", "INLINE_FRAGMENT"],
                                "args" => [
                                  %{
                                    "name" => "if",
                                    "description" => "Skipped when true",
                                    "type" => %{
                                      "kind" => "NON_NULL",
                                      "name" => nil,
                                      "ofType" => %{
                                        "kind" => "SCALAR",
                                        "name" => "Boolean",
                                        "ofType" => nil
                                      }
                                    },
                                    "defaultValue" => nil
                                  }
                                ]
                              }
                            ]
                          }
                        }
                      })

  describe "parse/1" do
    test "parses introspection JSON with data wrapper" do
      assert {:ok, schema} = Parser.parse(@introspection_json)
      assert %Schema{} = schema
      assert schema.query_type == "Query"
      assert schema.mutation_type == "Mutation"
      assert schema.subscription_type == nil
    end

    test "parses without data wrapper" do
      {:ok, decoded} = Jason.decode(@introspection_json)
      json = Jason.encode!(decoded["data"])
      assert {:ok, schema} = Parser.parse(json)
      assert schema.query_type == "Query"
    end

    test "parses object type with fields" do
      {:ok, schema} = Parser.parse(@introspection_json)
      assert {:ok, query_type} = Schema.get_type(schema, "Query")
      assert query_type.kind == :object
      assert query_type.description == "Root query type"
      assert query_type.interfaces == ["Node"]

      assert {:ok, user_field} = Schema.get_field(schema, "Query", "user")
      assert user_field.name == "user"
      assert user_field.description == "Fetch a user by ID"
      assert user_field.type.kind == :non_null
      assert user_field.type.of_type.kind == :object
      assert user_field.type.of_type.name == "User"
    end

    test "parses field arguments" do
      {:ok, schema} = Parser.parse(@introspection_json)
      {:ok, user_field} = Schema.get_field(schema, "Query", "user")

      assert %{"id" => id_arg} = user_field.args
      assert id_arg.name == "id"
      assert id_arg.description == "User ID"
      assert id_arg.type.kind == :non_null
      assert id_arg.type.of_type.kind == :scalar
      assert id_arg.type.of_type.name == "ID"
    end

    test "parses deprecated fields" do
      {:ok, schema} = Parser.parse(@introspection_json)
      {:ok, email_field} = Schema.get_field(schema, "User", "email")
      assert email_field.is_deprecated == true
      assert email_field.deprecation_reason == "Use emailAddress instead"
    end

    test "parses scalar type" do
      {:ok, schema} = Parser.parse(@introspection_json)
      {:ok, id_type} = Schema.get_type(schema, "ID")
      assert id_type.kind == :scalar
      assert id_type.description == "Built-in ID"
      assert id_type.fields == %{}
    end

    test "parses enum type with values" do
      {:ok, schema} = Parser.parse(@introspection_json)
      {:ok, role_type} = Schema.get_type(schema, "Role")
      assert role_type.kind == :enum
      assert length(role_type.enum_values) == 2

      [admin, user] = role_type.enum_values
      assert admin.name == "ADMIN"
      assert admin.description == "Administrator"
      assert user.name == "USER"
    end

    test "parses input object type" do
      {:ok, schema} = Parser.parse(@introspection_json)
      {:ok, input_type} = Schema.get_type(schema, "CreateUserInput")
      assert input_type.kind == :input_object
      assert %{"name" => name_field, "role" => role_field} = input_type.input_fields
      assert name_field.type.kind == :non_null
      assert role_field.default_value == "\"USER\""
    end

    test "parses directives" do
      {:ok, schema} = Parser.parse(@introspection_json)
      assert [skip] = schema.directives
      assert skip.name == "skip"
      assert skip.locations == [:field, :fragment_spread, :inline_fragment]
      assert %{"if" => if_arg} = skip.args
      assert if_arg.type.kind == :non_null
    end

    test "returns error for invalid JSON" do
      assert {:error, "JSON decode error:" <> _} = Parser.parse("not json")
    end

    test "returns error for missing __schema" do
      assert {:error, "invalid introspection result: missing __schema"} =
               Parser.parse(~s({"data": {}}))
    end
  end
end
