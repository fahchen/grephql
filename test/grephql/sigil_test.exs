defmodule Grephql.SigilTest do
  use ExUnit.Case, async: true

  alias Grephql.Query

  describe "~g sigil" do
    defmodule BasicQuery do
      use Grephql,
        otp_app: :grephql,
        source: "../support/schemas/minimal.json"

      @query ~g"query GetUser($id: ID!) { user(id: $id) { name email } }"

      def query_struct, do: @query
    end

    test "returns a Query struct" do
      assert %Query{} = BasicQuery.query_struct()
    end

    test "derives function_name from operation name" do
      query = BasicQuery.query_struct()
      assert query.operation_name == "GetUser"
      assert query.result_module == BasicQuery.GetUser
    end

    test "detects variables" do
      assert BasicQuery.query_struct().has_variables? == true
    end

    test "generates output type modules" do
      user = struct(BasicQuery.GetUser.User, name: "Alice", email: "a@b.com")
      assert user.name == "Alice"
      assert user.email == "a@b.com"
    end

    test "stores client_module" do
      assert BasicQuery.query_struct().client_module == BasicQuery
    end
  end

  describe "~g without variables" do
    defmodule NoVarsQuery do
      use Grephql,
        otp_app: :grephql,
        source: "../support/schemas/minimal.json"

      @query ~g"query CurrentUser { user(id: \"1\") { name } }"

      def query_struct, do: @query
    end

    test "has_variables? is false" do
      assert NoVarsQuery.query_struct().has_variables? == false
    end
  end

  describe "compile-time validation" do
    test "raises CompileError for anonymous operation" do
      assert_raise CompileError, ~r/requires a named operation/, fn ->
        defmodule AnonOp do
          use Grephql,
            otp_app: :grephql,
            source: "../support/schemas/minimal.json"

          @query ~g"query { user(id: \"1\") { name } }"
        end
      end
    end

    test "raises CompileError on invalid query syntax" do
      assert_raise CompileError, ~r/parse error/, fn ->
        defmodule InvalidSyntax do
          use Grephql,
            otp_app: :grephql,
            source: "../support/schemas/minimal.json"

          @query ~g"query Bad { ??? }"
        end
      end
    end

    test "raises CompileError on validation error" do
      assert_raise CompileError, ~r/validation errors/, fn ->
        defmodule InvalidField do
          use Grephql,
            otp_app: :grephql,
            source: "../support/schemas/minimal.json"

          @query ~g"query Bad { nonExistentField { name } }"
        end
      end
    end
  end

  describe "interpolation" do
    defmodule InterpolatedQuery do
      use Grephql,
        otp_app: :grephql,
        source: "../support/schemas/minimal.json"

      @fields "name email"
      @query ~g"query GetUser($id: ID!) { user(id: $id) { #{@fields} } }"

      def query_struct, do: @query
    end

    test "supports module attribute interpolation" do
      query = InterpolatedQuery.query_struct()
      assert query.operation_name == "GetUser"
      assert query.result_module == InterpolatedQuery.GetUser
    end

    test "generates types from interpolated fields" do
      user = struct(InterpolatedQuery.GetUser.User, name: "Alice", email: "a@b.com")
      assert user.name == "Alice"
      assert user.email == "a@b.com"
    end
  end
end
