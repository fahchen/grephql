defmodule Grephql.InputTypeGeneratorTest do
  use ExUnit.Case, async: true

  # Suppress warnings for modules created at runtime by InputTypeGenerator
  @compile {:no_warn_undefined,
            [
              Grephql.Test.Input.Basic.Inputs.CreateUserInput,
              Grephql.Test.Input.Build.Inputs.CreateUserInput,
              Grephql.Test.Input.Required.Inputs.CreateUserInput,
              Grephql.Test.Input.Nullable.Inputs.CreateUserInput,
              Grephql.Test.Input.Nested.Inputs.CreateUserInput,
              Grephql.Test.Input.Nested.Inputs.AddressInput,
              Grephql.Test.Input.NestedBuild.Inputs.CreateUserInput,
              Grephql.Test.Input.Dedup.Inputs.SharedInput,
              Grephql.Test.Var.Scalar.GetUser.Variables,
              Grephql.Test.Var.Required.GetUser.Variables,
              Grephql.Test.Var.Camel.GetUser.Variables,
              Grephql.Test.Var.Embed.Inputs.CreateUserInput,
              Grephql.Test.Var.Embed.CreateUser.Variables,
              Grephql.Test.Var.Mixed.Inputs.CreateUserInput,
              Grephql.Test.Var.Mixed.CreateUser.Variables,
              Grephql.Test.Var.Dump.Inputs.CreateUserInput,
              Grephql.Test.Var.Dump.CreateUser.Variables,
              Grephql.Test.Var.Params.GetUser.Variables,
              Grephql.Test.Var.ParamsEmbed.Inputs.CreateUserInput,
              Grephql.Test.Var.ParamsEmbed.CreateUser.Variables,
              Grephql.Test.Input.Params.Inputs.CreateUserInput
            ]}

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

  describe "generate_variables/3" do
    test "generates Variables struct with scalar fields" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query GetUser($id: ID!) { user(id: $id) { name } }")

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: Grephql.Test.Var.Scalar,
          function_name: :get_user,
          scalar_types: %{}
        )

      assert variables_module == Grephql.Test.Var.Scalar.GetUser.Variables

      fields = variables_module.__schema__(:fields)
      assert :id in fields
    end

    test "build/1 validates required scalar variables" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query GetUser($id: ID!) { user(id: $id) { name } }")

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: Grephql.Test.Var.Required,
          function_name: :get_user,
          scalar_types: %{}
        )

      assert {:ok, vars} = variables_module.build(%{id: "123"})
      assert vars.id == "123"

      assert {:error, changeset} = variables_module.build(%{})
      assert "can't be blank" in errors_on(changeset, :id)
    end

    test "returns nil for operations without variables" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name } }")

      assert nil ==
               InputTypeGenerator.generate_variables(operation, schema,
                 client_module: Grephql.Test.Var.NoVars,
                 function_name: :get_user,
                 scalar_types: %{}
               )
    end

    test "uses source mapping for camelCase variable names" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query GetUser($userId: ID!) { user(id: $userId) { name } }")

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: Grephql.Test.Var.Camel,
          function_name: :get_user,
          scalar_types: %{}
        )

      assert {:ok, vars} = variables_module.build(%{user_id: "123"})
      assert vars.user_id == "123"

      dumped = Ecto.embedded_dump(vars, :json)
      assert dumped[:userId] == "123"
    end

    test "embeds input object variables" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.Var.Embed,
        scalar_types: %{}
      )

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: Grephql.Test.Var.Embed,
          function_name: :create_user,
          scalar_types: %{}
        )

      assert variables_module == Grephql.Test.Var.Embed.CreateUser.Variables
      assert :input in variables_module.__schema__(:embeds)

      assert {:ok, vars} =
               variables_module.build(%{input: %{name: "Alice", email: "a@b.com"}})

      assert vars.input.name == "Alice"
    end

    test "mixes scalar and input object variables" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($id: ID!, $input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.Var.Mixed,
        scalar_types: %{}
      )

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: Grephql.Test.Var.Mixed,
          function_name: :create_user,
          scalar_types: %{}
        )

      fields = variables_module.__schema__(:fields)
      embeds = variables_module.__schema__(:embeds)
      assert :id in fields
      assert :input in embeds

      assert {:ok, vars} =
               variables_module.build(%{id: "1", input: %{name: "Alice"}})

      assert vars.id == "1"
      assert vars.input.name == "Alice"
    end

    test "embedded_dump serializes correctly for GraphQL" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.Var.Dump,
        scalar_types: %{}
      )

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: Grephql.Test.Var.Dump,
          function_name: :create_user,
          scalar_types: %{}
        )

      {:ok, vars} = variables_module.build(%{input: %{name: "Alice", email: "a@b.com"}})
      dumped = Ecto.embedded_dump(vars, :json)

      assert dumped[:input][:name] == "Alice"
      assert dumped[:input][:email] == "a@b.com"
    end
  end

  describe "params() type generation" do
    test "Variables module with params() compiles successfully" do
      schema = SchemaHelper.build_schema()
      operation = parse!("query GetUser($id: ID!) { user(id: $id) { name } }")

      # params() type is injected at compilation — if this doesn't raise, it compiled
      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: Grephql.Test.Var.Params,
          function_name: :get_user,
          scalar_types: %{}
        )

      # Module is functional with build/1
      assert {:ok, vars} = variables_module.build(%{id: "123"})
      assert vars.id == "123"
    end

    test "Input type modules with params() compile successfully" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      modules =
        InputTypeGenerator.generate(operation, schema,
          client_module: Grephql.Test.Input.Params,
          scalar_types: %{}
        )

      input_module = hd(modules)
      assert {:ok, _struct} = input_module.build(%{name: "Alice"})
    end

    test "Variables with embed params() compiles and builds correctly" do
      schema = schema_with_input()

      operation =
        parse!(
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { name } }"
        )

      InputTypeGenerator.generate(operation, schema,
        client_module: Grephql.Test.Var.ParamsEmbed,
        scalar_types: %{}
      )

      variables_module =
        InputTypeGenerator.generate_variables(operation, schema,
          client_module: Grephql.Test.Var.ParamsEmbed,
          function_name: :create_user,
          scalar_types: %{}
        )

      assert {:ok, vars} = variables_module.build(%{input: %{name: "Alice"}})
      assert vars.input.name == "Alice"
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
