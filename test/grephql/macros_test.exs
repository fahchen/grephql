defmodule Grephql.MacrosTest do
  use ExUnit.Case, async: true

  alias Grephql.Macros
  alias Grephql.Query

  describe "__build_doc__/1" do
    test "query with variables" do
      query = %Query{
        document: "query GetUser($id: ID!) { user(id: $id) { name } }",
        operation_name: "GetUser",
        operation_type: "query",
        result_module: MyApp.GetUser.Result,
        variables_module: MyApp.GetUser.Variables,
        client_module: MyApp.Client,
        has_variables?: true,
        variable_docs: [
          %{name: "id", type: "ID!", required: true}
        ]
      }

      doc = Macros.__build_doc__(query)

      assert doc =~ "Executes the `GetUser` GraphQL query."
      assert doc =~ "| `id` | `ID!` | required |"
      assert doc =~ "`MyApp.GetUser.Result` — result type"
      assert doc =~ "`MyApp.GetUser.Variables` — variables type"
    end

    test "query without variables" do
      query = %Query{
        document: "query { users { name } }",
        operation_type: "query",
        result_module: MyApp.ListUsers.Result,
        client_module: MyApp.Client
      }

      doc = Macros.__build_doc__(query)

      assert doc =~ "Executes a GraphQL query."
      refute doc =~ "## Variables"
      assert doc =~ "`MyApp.ListUsers.Result` — result type"
      refute doc =~ "variables type"
    end

    test "mutation with input types" do
      query = %Query{
        document:
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { id } }",
        operation_name: "CreateUser",
        operation_type: "mutation",
        result_module: MyApp.CreateUser.Result,
        variables_module: MyApp.CreateUser.Variables,
        input_modules: [MyApp.Inputs.CreateUserInput],
        client_module: MyApp.Client,
        has_variables?: true,
        variable_docs: [
          %{name: "input", type: "CreateUserInput!", required: true}
        ]
      }

      doc = Macros.__build_doc__(query)

      assert doc =~ "Executes the `CreateUser` GraphQL mutation."
      assert doc =~ "`MyApp.Inputs.CreateUserInput` — input type"
    end

    test "multiple variables with mixed nullability" do
      query = %Query{
        document: "query($id: ID!, $name: String) { user(id: $id) { name } }",
        operation_type: "query",
        result_module: MyApp.Search.Result,
        variables_module: MyApp.Search.Variables,
        client_module: MyApp.Client,
        has_variables?: true,
        variable_docs: [
          %{name: "id", type: "ID!", required: true},
          %{name: "name", type: "String", required: false}
        ]
      }

      doc = Macros.__build_doc__(query)

      assert doc =~ "| `id` | `ID!` | required |"
      assert doc =~ "| `name` | `String` | optional |"
    end
  end
end
