defmodule Grephql.DefgqlTest do
  use ExUnit.Case, async: true

  alias Grephql.Query

  describe "defgql with variables" do
    defmodule WithVariables do
      use Grephql,
        otp_app: :grephql,
        source: "../support/schemas/minimal.json"

      defgql(:get_user, "query GetUser($id: ID!) { user(id: $id) { name email } }")
    end

    test "generates a 2-arity function (variables + opts)" do
      assert function_exported?(WithVariables, :get_user, 2)
      assert function_exported?(WithVariables, :get_user, 1)
    end

    test "function returns execute result" do
      assert {:error, :not_implemented} = WithVariables.get_user(%{id: "1"})
    end

    test "generates output type modules" do
      user = struct(WithVariables.GetUser.User, name: "Alice", email: "a@b.com")
      assert user.name == "Alice"
      assert user.email == "a@b.com"
    end
  end

  describe "defgql without variables" do
    defmodule WithoutVariables do
      use Grephql,
        otp_app: :grephql,
        source: "../support/schemas/minimal.json"

      defgql(:get_user, "query { user(id: \"1\") { name } }")
    end

    test "generates a 1-arity function (opts only)" do
      assert function_exported?(WithoutVariables, :get_user, 1)
      assert function_exported?(WithoutVariables, :get_user, 0)
    end

    test "function returns execute result" do
      assert {:error, :not_implemented} = WithoutVariables.get_user()
    end
  end

  describe "defgqlp" do
    defmodule PrivateQuery do
      use Grephql,
        otp_app: :grephql,
        source: "../support/schemas/minimal.json"

      defgqlp(:get_user_private, "query($id: ID!) { user(id: $id) { name } }")

      def call_private(variables), do: get_user_private(variables)
    end

    test "generates a private function" do
      refute function_exported?(PrivateQuery, :get_user_private, 2)
    end

    test "private function is callable from within the module" do
      assert {:error, :not_implemented} = PrivateQuery.call_private(%{id: "1"})
    end
  end

  describe "compile-time validation" do
    test "raises CompileError on invalid query syntax" do
      assert_raise CompileError, ~r/parse error/, fn ->
        defmodule InvalidSyntax do
          use Grephql,
            otp_app: :grephql,
            source: "../support/schemas/minimal.json"

          defgql(:bad, "query { ??? }")
        end
      end
    end

    test "raises CompileError on validation error" do
      assert_raise CompileError, ~r/validation errors/, fn ->
        defmodule InvalidField do
          use Grephql,
            otp_app: :grephql,
            source: "../support/schemas/minimal.json"

          defgql(:bad, "query { nonExistentField { name } }")
        end
      end
    end

    test "raises CompileError when multiple operations in one defgql" do
      assert_raise CompileError, ~r/multiple operation definitions/, fn ->
        defmodule MultipleOps do
          use Grephql,
            otp_app: :grephql,
            source: "../support/schemas/minimal.json"

          defgql(:bad, """
          query GetUser($id: ID!) { user(id: $id) { name } }
          query ListUsers { users { name } }
          """)
        end
      end
    end
  end

  describe "query struct" do
    defmodule QueryInspect do
      use Grephql,
        otp_app: :grephql,
        source: "../support/schemas/minimal.json"

      defgql(:get_user, "query GetUser($id: ID!) { user(id: $id) { name } }")

      def query_struct, do: @grephql_query
    end

    test "stores Query struct as module attribute" do
      query = QueryInspect.query_struct()
      assert %Query{} = query
      assert query.operation_name == "GetUser"
      assert query.has_variables? == true
      assert query.client_module == QueryInspect
      assert query.result_module == QueryInspect.GetUser
    end
  end
end
