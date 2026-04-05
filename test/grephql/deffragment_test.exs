defmodule Grephql.DeffragmentTest do
  use ExUnit.Case, async: true

  describe "deffragment basic" do
    defmodule BasicClient do
      use Grephql,
        otp_app: :grephql,
        source: "../support/schemas/minimal.json"

      deffragment(:user_fields, ~GQL"""
      fragment UserFields on User {
        name
        email
      }
      """)

      defgql(:get_user, ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          ...UserFields
        }
      }
      """)

      def query, do: @grephql_query
    end

    test "generates function with fragment spread" do
      assert function_exported?(BasicClient, :get_user, 2)
    end

    test "generates result struct with fragment fields" do
      user = struct(BasicClient.GetUser.Result.User, name: "Alice", email: "a@b.com")
      assert user.name == "Alice"
      assert user.email == "a@b.com"
    end

    test "generates fragment module under Fragments namespace" do
      assert Code.ensure_loaded?(BasicClient.Fragments.UserFields)
      frag = struct(BasicClient.Fragments.UserFields, name: "Alice", email: "a@b.com")
      assert frag.name == "Alice"
      assert frag.email == "a@b.com"
    end

    test "query document includes fragment definition" do
      assert BasicClient.query().document =~ "fragment UserFields on User"
      assert BasicClient.query().document =~ "...UserFields"
    end
  end

  describe "deffragment with plain string" do
    defmodule PlainStringClient do
      use Grephql,
        otp_app: :grephql,
        source: "../support/schemas/minimal.json"

      deffragment(:user_name, "fragment UserName on User { name }")

      defgql(:get_user, ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          ...UserName
        }
      }
      """)
    end

    test "plain string fragment works" do
      assert function_exported?(PlainStringClient, :get_user, 2)
    end

    test "generates result with fragment fields" do
      user = struct(PlainStringClient.GetUser.Result.User, name: "Alice")
      assert user.name == "Alice"
    end
  end

  describe "deffragment with mixed fields" do
    defmodule MixedClient do
      use Grephql,
        otp_app: :grephql,
        source: "../support/schemas/minimal.json"

      deffragment(:user_email, ~GQL"""
      fragment UserEmail on User {
        email
      }
      """)

      defgql(:get_user, ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          name
          ...UserEmail
        }
      }
      """)
    end

    test "combines direct fields and fragment fields" do
      user = struct(MixedClient.GetUser.Result.User, name: "Alice", email: "a@b.com")
      assert user.name == "Alice"
      assert user.email == "a@b.com"
    end
  end

  describe "nested fragments" do
    defmodule NestedClient do
      use Grephql,
        otp_app: :grephql,
        source: "../support/schemas/minimal.json"

      deffragment(:user_name, ~GQL"""
      fragment UserName on User {
        name
      }
      """)

      deffragment(:user_details, ~GQL"""
      fragment UserDetails on User {
        ...UserName
        email
      }
      """)

      defgql(:get_user, ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          ...UserDetails
        }
      }
      """)

      def query, do: @grephql_query
    end

    test "resolves nested fragment dependencies" do
      assert function_exported?(NestedClient, :get_user, 2)
    end

    test "generates all fields from nested fragments" do
      user = struct(NestedClient.GetUser.Result.User, name: "Alice", email: "a@b.com")
      assert user.name == "Alice"
      assert user.email == "a@b.com"
    end

    test "generates fragment modules for each deffragment" do
      assert Code.ensure_loaded?(NestedClient.Fragments.UserName)
      assert Code.ensure_loaded?(NestedClient.Fragments.UserDetails)
    end

    test "query document includes both fragment definitions" do
      assert NestedClient.query().document =~ "fragment UserDetails on User"
      assert NestedClient.query().document =~ "fragment UserName on User"
    end
  end

  describe "query without fragments" do
    defmodule NoFragmentClient do
      use Grephql,
        otp_app: :grephql,
        source: "../support/schemas/minimal.json"

      deffragment(:unused_fields, ~GQL"""
      fragment UnusedFields on User {
        name
      }
      """)

      defgql(:get_user, ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          name
          email
        }
      }
      """)

      def query, do: @grephql_query
    end

    test "does not append unused fragments" do
      refute NoFragmentClient.query().document =~ "fragment UnusedFields"
    end
  end

  describe "compile errors" do
    test "fragment with invalid type condition raises" do
      assert_raise CompileError, ~r/does not exist in the schema/, fn ->
        Code.compile_string("""
        defmodule Grephql.Test.InvalidTypeFragment do
          use Grephql,
            otp_app: :grephql,
            source: "test/support/schemas/minimal.json"

          deffragment :bad, "fragment Bad on NonExistentType { name }"
        end
        """)
      end
    end

    test "fragment with invalid field raises" do
      assert_raise CompileError, ~r/does not exist on type/, fn ->
        Code.compile_string("""
        defmodule Grephql.Test.InvalidFieldFragment do
          use Grephql,
            otp_app: :grephql,
            source: "test/support/schemas/minimal.json"

          deffragment :bad, "fragment Bad on User { nonExistentField }"
        end
        """)
      end
    end
  end
end
