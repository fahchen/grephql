defmodule TypedGql.Integration.MutationVariablesFailingChangesetValidationBeforeAnyRequestTest do
  @moduledoc """
  Invalid mutation variables never reach the wire:

  - missing required nested fields fail with "can't be blank"
  - a wrong-typed nested value returns a changeset error instead of crashing
  - neither case makes an HTTP request (no `Req.Test` expectation is ever set)
  """
  use TypedGql.IntegrationCase, async: true

  import TypedGql.Test.Helpers, only: [errors_on: 2]

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql",
      req_options: [
        plug: {Req.Test, __MODULE__}
      ]

    defgql(:create_user, """
    mutation CreateUser($input: CreateUserInput!) {
      createUser(input: $input) {
        id
        name
      }
    }
    """)
  end

  # No Req.Test.expect is registered anywhere in this file: verify_on_exit!
  # with zero expectations proves that none of the calls below ever issued an
  # HTTP request.

  describe "changeset validation" do
    test "missing required nested fields fail with can't be blank before any request" do
      assert {:error, %Ecto.Changeset{} = changeset} = call(%{input: %{}})

      input_changeset = changeset.changes.input
      assert "can't be blank" in errors_on(input_changeset, :name)
      assert "can't be blank" in errors_on(input_changeset, :email)
    end

    test "a wrong-typed nested value returns a changeset error instead of crashing" do
      assert {:error, %Ecto.Changeset{} = changeset} =
               call(%{input: %{name: "Alice", email: "alice@example.com", profile: "not-a-map"}})

      assert "is invalid" in errors_on(changeset.changes.input, :profile)
    end
  end

  defp call(variables) do
    Client.create_user(variables)
  end
end
