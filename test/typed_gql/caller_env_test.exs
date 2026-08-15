defmodule TypedGql.CallerEnvTest do
  use ExUnit.Case, async: true

  @compile {:no_warn_undefined,
            [
              TypedGql.Test.CallerEnv.Result.GetUser.Result.User,
              TypedGql.Test.CallerEnv.Vars.GetUser.Variables,
              TypedGql.Test.CallerEnv.Input.Inputs.CreateUserInput
            ]}

  alias TypedGql.GeneratorHelpers
  alias TypedGql.InputTypeGenerator
  alias TypedGql.Test.SchemaHelper
  alias TypedGql.TypeGenerator

  describe "GeneratorHelpers.location_from/1" do
    test "returns the Macro.Env location for a Macro.Env" do
      env = __ENV__
      assert GeneratorHelpers.location_from(env) == Macro.Env.location(env)
      assert [file: _file, line: _line] = GeneratorHelpers.location_from(env)
    end

    test "raises ArgumentError for a non-Macro.Env value" do
      assert_raise ArgumentError, ~r/expected caller_env to be a Macro.Env/, fn ->
        GeneratorHelpers.location_from("not an env")
      end

      assert_raise ArgumentError, ~r/expected caller_env to be a Macro.Env/, fn ->
        GeneratorHelpers.location_from(nil)
      end
    end
  end

  describe "generated module source location" do
    test "result module records the caller file" do
      caller_file = __ENV__.file
      schema = SchemaHelper.build_schema()
      operation = parse!("query { user(id: \"1\") { name } }")

      TypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.CallerEnv.Result,
        function_name: :get_user,
        caller_env: __ENV__
      )

      source =
        TypedGql.Test.CallerEnv.Result.GetUser.Result.User.__info__(:compile)[:source]

      assert source == String.to_charlist(caller_file)
    end

    test "variables module records the caller file" do
      caller_file = __ENV__.file
      schema = SchemaHelper.build_schema()
      operation = parse!("query ($id: ID!) { user(id: $id) { name } }")

      InputTypeGenerator.generate_variables(operation, schema,
        client_module: TypedGql.Test.CallerEnv.Vars,
        function_name: :get_user,
        caller_env: __ENV__
      )

      source = TypedGql.Test.CallerEnv.Vars.GetUser.Variables.__info__(:compile)[:source]
      assert source == String.to_charlist(caller_file)
    end

    test "input module records the caller file" do
      caller_file = __ENV__.file
      schema = schema_with_input()

      operation =
        parse!("mutation ($input: CreateUserInput!) { createUser(input: $input) { name } }")

      InputTypeGenerator.generate(operation, schema,
        client_module: TypedGql.Test.CallerEnv.Input,
        caller_env: __ENV__
      )

      source = TypedGql.Test.CallerEnv.Input.Inputs.CreateUserInput.__info__(:compile)[:source]
      assert source == String.to_charlist(caller_file)
    end
  end

  defp parse!(query) do
    {:ok, %{definitions: [operation | _rest]}} = TypedGql.Parser.parse(query)
    operation
  end

  defp schema_with_input do
    types =
      Map.merge(SchemaHelper.default_types(), %{
        "Mutation" => %TypedGql.Schema.Type{
          kind: :object,
          name: "Mutation",
          fields: %{
            "createUser" => %TypedGql.Schema.Field{
              name: "createUser",
              type: %TypedGql.Schema.TypeRef{kind: :object, name: "User"},
              args: %{
                "input" => %TypedGql.Schema.InputValue{
                  name: "input",
                  type: %TypedGql.Schema.TypeRef{
                    kind: :non_null,
                    of_type: %TypedGql.Schema.TypeRef{
                      kind: :input_object,
                      name: "CreateUserInput"
                    }
                  }
                }
              }
            }
          }
        },
        "CreateUserInput" => %TypedGql.Schema.Type{
          kind: :input_object,
          name: "CreateUserInput",
          input_fields: %{
            "name" => %TypedGql.Schema.InputValue{
              name: "name",
              type: %TypedGql.Schema.TypeRef{
                kind: :non_null,
                of_type: %TypedGql.Schema.TypeRef{kind: :scalar, name: "String"}
              }
            }
          }
        }
      })

    SchemaHelper.build_schema(types: types, mutation_type: "Mutation")
  end
end
