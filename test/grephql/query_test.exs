defmodule Grephql.QueryTest do
  use ExUnit.Case, async: true

  alias Grephql.Query

  describe "struct" do
    test "creates with required fields" do
      query = %Query{
        document: "query { user { name } }",
        operation_type: "query",
        result_module: MyApp.GetUser,
        client_module: MyApp.Client
      }

      assert query.document == "query { user { name } }"
      assert query.result_module == MyApp.GetUser
      assert query.client_module == MyApp.Client
    end

    test "defaults optional fields" do
      query = %Query{
        document: "query { user { name } }",
        operation_type: "query",
        result_module: MyApp.GetUser,
        client_module: MyApp.Client
      }

      assert query.operation_name == nil
      assert query.input_modules == []
      assert query.has_variables? == false
    end

    test "creates with all fields" do
      query = %Query{
        document: "query GetUser($id: ID!) { user(id: $id) { name } }",
        operation_name: "GetUser",
        operation_type: "query",
        result_module: MyApp.GetUser,
        input_modules: [MyApp.Inputs.CreateUserInput],
        client_module: MyApp.Client,
        has_variables?: true
      }

      assert query.operation_name == "GetUser"
      assert query.input_modules == [MyApp.Inputs.CreateUserInput]
      assert query.has_variables? == true
    end

    test "enforces required fields" do
      assert_raise ArgumentError, fn ->
        struct!(Query, document: "query { user { name } }")
      end
    end
  end
end
