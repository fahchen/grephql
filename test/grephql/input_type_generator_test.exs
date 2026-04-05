defmodule Grephql.InputTypeGeneratorTest do
  use ExUnit.Case, async: true

  alias Grephql.InputTypeGenerator
  alias Grephql.Schema.Field, as: SchemaField
  alias Grephql.Schema.InputValue
  alias Grephql.Schema.Type
  alias Grephql.Schema.TypeRef
  alias Grephql.Test.SchemaHelper

  describe "basic input type generation" do
    test "generates embedded schema for input type with scalar fields" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      modules =
        InputTypeGenerator.generate(operation, schema,
          client_module: Grephql.Test.Input.Basic,
          scalar_types: %{}
        )

      assert Grephql.Test.Input.Basic.Inputs.CreateUserInput in modules

      fields = Grephql.Test.Input.Basic.Inputs.CreateUserInput.__schema__(:fields)
      assert :name in fields
      assert :email in fields
    end

    test "build/1 succeeds with valid params" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.Input.Build,
        scalar_types: %{}
      )

      assert {:ok, struct} =
               Grephql.Test.Input.Build.Inputs.CreateUserInput.build(%{
                 name: "Alice",
                 email: "a@b.com"
               })

      assert struct.name == "Alice"
      assert struct.email == "a@b.com"
    end

    test "build/1 fails when required field is missing" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.Input.Required,
        scalar_types: %{}
      )

      assert {:error, changeset} =
               Grephql.Test.Input.Required.Inputs.CreateUserInput.build(%{email: "a@b.com"})

      assert "can't be blank" in errors_on(changeset, :name)
    end

    test "nullable field defaults to nil" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.Input.Nullable,
        scalar_types: %{}
      )

      assert {:ok, struct} =
               Grephql.Test.Input.Nullable.Inputs.CreateUserInput.build(%{name: "Alice"})

      assert struct.email == nil
    end
  end

  describe "nested input types" do
    test "generates nested input type with embeds_one" do
      schema = schema_with_nested_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      modules =
        InputTypeGenerator.generate(operation, schema,
          client_module: Grephql.Test.Input.Nested,
          scalar_types: %{}
        )

      assert Grephql.Test.Input.Nested.Inputs.CreateUserInput in modules
      assert Grephql.Test.Input.Nested.Inputs.AddressInput in modules

      assert :address in Grephql.Test.Input.Nested.Inputs.CreateUserInput.__schema__(:embeds)
    end

    test "build/1 with nested input succeeds" do
      schema = schema_with_nested_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.Input.NestedBuild,
        scalar_types: %{}
      )

      assert {:ok, struct} =
               Grephql.Test.Input.NestedBuild.Inputs.CreateUserInput.build(%{
                 name: "Alice",
                 address: %{city: "NYC", street: "123 Main St"}
               })

      assert struct.name == "Alice"
      assert struct.address.city == "NYC"
      assert struct.address.street == "123 Main St"
    end
  end

  describe "deduplication" do
    test "same input type referenced twice generates only once" do
      schema = schema_with_shared_input()

      operation =
        parse!("mutation Op($a: SharedInput!, $b: SharedInput!) { doA(input: $a) { name } }")

      modules =
        InputTypeGenerator.generate(operation, schema,
          client_module: Grephql.Test.Input.Dedup,
          scalar_types: %{}
        )

      shared_count = Enum.count(modules, &(&1 == Grephql.Test.Input.Dedup.Inputs.SharedInput))
      assert shared_count == 1
    end
  end

  describe "scalar-only variables are skipped" do
    test "does not generate modules for scalar variables" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query GetUser($id: ID!) { user(id: $id) { name } }")

      modules =
        InputTypeGenerator.generate(operation, schema,
          client_module: Grephql.Test.Input.Scalar,
          scalar_types: %{}
        )

      assert modules == []
    end
  end

  # Helpers

  defp parse!(query) do
    {:ok, %{definitions: [operation | _rest]}} = Grephql.Parser.parse(query)
    operation
  end

  defp errors_on(changeset, field) do
    changeset.errors
    |> Keyword.get_values(field)
    |> Enum.map(fn {msg, _opts} -> msg end)
  end

  defp schema_with_input do
    types =
      Map.merge(SchemaHelper.default_types(), %{
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
              type: %TypeRef{
                kind: :non_null,
                of_type: %TypeRef{kind: :scalar, name: "String"}
              }
            },
            "email" => %InputValue{
              name: "email",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types, mutation_type: "Mutation")
  end

  defp schema_with_nested_input do
    types =
      Map.merge(SchemaHelper.default_types(), %{
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
              type: %TypeRef{
                kind: :non_null,
                of_type: %TypeRef{kind: :scalar, name: "String"}
              }
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
              type: %TypeRef{
                kind: :non_null,
                of_type: %TypeRef{kind: :scalar, name: "String"}
              }
            },
            "street" => %InputValue{
              name: "street",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types, mutation_type: "Mutation")
  end

  defp schema_with_shared_input do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Mutation" => %Type{
          kind: :object,
          name: "Mutation",
          fields: %{
            "doA" => %SchemaField{
              name: "doA",
              type: %TypeRef{kind: :object, name: "User"},
              args: %{
                "input" => %InputValue{
                  name: "input",
                  type: %TypeRef{
                    kind: :non_null,
                    of_type: %TypeRef{kind: :input_object, name: "SharedInput"}
                  }
                }
              }
            }
          }
        },
        "SharedInput" => %Type{
          kind: :input_object,
          name: "SharedInput",
          input_fields: %{
            "value" => %InputValue{
              name: "value",
              type: %TypeRef{kind: :scalar, name: "String"}
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types, mutation_type: "Mutation")
  end
end
