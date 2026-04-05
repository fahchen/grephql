defmodule Grephql.SigilTest do
  use ExUnit.Case, async: true

  describe "~GQL sigil returns plain string" do
    defmodule StringCheck do
      use Grephql,
        otp_app: :grephql,
        source: "../support/schemas/minimal.json"

      @gql_string ~GQL"query GetUser($id: ID!) {
  user(id: $id) {
    name
  }
}"

      def gql_string, do: @gql_string
    end

    test "~GQL returns a binary string" do
      assert is_binary(StringCheck.gql_string())
      assert StringCheck.gql_string() =~ "query GetUser"
    end
  end

  describe "defgql with ~GQL heredoc" do
    defmodule HeredocClient do
      use Grephql,
        otp_app: :grephql,
        source: "../support/schemas/minimal.json"

      defgql(:get_user, ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          name
          email
        }
      }
      """)

      defgql(:current_user, ~GQL"""
      query CurrentUser {
        user(id: "1") {
          name
        }
      }
      """)
    end

    test "generates function with variables" do
      assert function_exported?(HeredocClient, :get_user, 2)
    end

    test "generates function without variables" do
      assert function_exported?(HeredocClient, :current_user, 1)
    end

    test "compiles query struct with correct metadata" do
      # Verify the module compiled successfully with proper type generation
      user = struct(HeredocClient.GetUser.Result.User, name: "Alice", email: "a@b.com")
      assert user.name == "Alice"
      assert user.email == "a@b.com"
    end
  end

  describe "defgql with plain string" do
    defmodule PlainStringClient do
      use Grephql,
        otp_app: :grephql,
        source: "../support/schemas/minimal.json"

      defgql(:get_user, "query GetUser($id: ID!) { user(id: $id) { name email } }")
    end

    test "plain string generates function" do
      assert function_exported?(PlainStringClient, :get_user, 2)
    end

    test "plain string with interpolation generates function" do
      defmodule InterpolatedClient do
        use Grephql,
          otp_app: :grephql,
          source: "../support/schemas/minimal.json"

        @fields "name email"
        defgql(:get_user, "query GetUser($id: ID!) { user(id: $id) { #{@fields} } }")
      end

      assert function_exported?(InterpolatedClient, :get_user, 2)
    end
  end
end
