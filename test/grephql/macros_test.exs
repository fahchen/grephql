defmodule Grephql.MacrosTest do
  use ExUnit.Case, async: true

  alias Grephql.Macros
  alias Grephql.Query

  @client MyApp.GitHub

  describe "__build_doc__/1" do
    test "query with variables and nested modules" do
      query = %Query{
        document: "query GetUser($id: ID!) { user(id: $id) { name } }",
        operation_name: "GetUser",
        operation_type: "query",
        result_module: MyApp.GitHub.GetUser.Result,
        result_modules: [MyApp.GitHub.GetUser.Result, MyApp.GitHub.GetUser.Result.User],
        variables_module: MyApp.GitHub.GetUser.Variables,
        client_module: @client,
        has_variables?: true,
        variable_docs: [
          %{name: "id", type: "ID!", required: true}
        ]
      }

      doc = Macros.__build_doc__(query)

      assert doc =~ "Executes the `GetUser` GraphQL query."
      assert doc =~ "| `id` | `ID!` | required |"
      assert doc =~ ~s|`\#{__MODULE__}.GetUser.Result`|
      assert doc =~ ~s|`\#{__MODULE__}.GetUser.Result.User`|
      assert doc =~ ~s|`\#{__MODULE__}.GetUser.Variables`|
    end

    test "query without variables" do
      query = %Query{
        document: "query { users { name } }",
        operation_type: "query",
        result_module: MyApp.GitHub.ListUsers.Result,
        result_modules: [MyApp.GitHub.ListUsers.Result],
        client_module: @client
      }

      doc = Macros.__build_doc__(query)

      assert doc =~ "Executes a GraphQL query."
      refute doc =~ "## Variables"
      assert doc =~ ~s|`\#{__MODULE__}.ListUsers.Result`|
      refute doc =~ "Variables`"
    end

    test "mutation with input types" do
      query = %Query{
        document:
          "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { id } }",
        operation_name: "CreateUser",
        operation_type: "mutation",
        result_module: MyApp.GitHub.CreateUser.Result,
        result_modules: [MyApp.GitHub.CreateUser.Result],
        variables_module: MyApp.GitHub.CreateUser.Variables,
        input_modules: [MyApp.GitHub.Inputs.CreateUserInput],
        client_module: @client,
        has_variables?: true,
        variable_docs: [
          %{name: "input", type: "CreateUserInput!", required: true}
        ]
      }

      doc = Macros.__build_doc__(query)

      assert doc =~ "Executes the `CreateUser` GraphQL mutation."
      assert doc =~ ~s|`\#{__MODULE__}.Inputs.CreateUserInput`|
    end

    test "multiple variables with mixed nullability" do
      query = %Query{
        document: "query($id: ID!, $name: String) { user(id: $id) { name } }",
        operation_type: "query",
        result_module: MyApp.GitHub.Search.Result,
        result_modules: [MyApp.GitHub.Search.Result],
        variables_module: MyApp.GitHub.Search.Variables,
        client_module: @client,
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

    test "lists deeply nested result modules" do
      query = %Query{
        document: "query { user { name posts { title author { name } } } }",
        operation_type: "query",
        result_module: MyApp.GitHub.GetUser.Result,
        result_modules: [
          MyApp.GitHub.GetUser.Result,
          MyApp.GitHub.GetUser.Result.User,
          MyApp.GitHub.GetUser.Result.User.Posts,
          MyApp.GitHub.GetUser.Result.User.Posts.Author
        ],
        client_module: @client
      }

      doc = Macros.__build_doc__(query)

      assert doc =~ ~s|`\#{__MODULE__}.GetUser.Result`|
      assert doc =~ ~s|`\#{__MODULE__}.GetUser.Result.User`|
      assert doc =~ ~s|`\#{__MODULE__}.GetUser.Result.User.Posts`|
      assert doc =~ ~s|`\#{__MODULE__}.GetUser.Result.User.Posts.Author`|
    end
  end
end
