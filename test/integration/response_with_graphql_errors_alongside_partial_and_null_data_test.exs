defmodule TypedGql.Integration.ResponseWithGraphqlErrorsAlongsidePartialAndNullDataTest do
  @moduledoc """
  GraphQL-level errors coexisting with data in the Result struct:

  - partial data decodes even when the response carries field errors
  - errors arrive as `TypedGql.Error` structs with message, path, locations, and extensions
  - an error without path, locations, or extensions decodes those fields as nil
  - null data with errors still returns `:ok`, keeping data nil and every error
  - a clean response leaves errors as an empty list
  """
  use TypedGql.IntegrationCase, async: true

  alias TypedGql.Error

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql",
      req_options: [
        plug: {Req.Test, __MODULE__}
      ]

    defgql(:get_user, """
    query GetUser($id: ID!) {
      user(id: $id) {
        id
        name
        email
        role
      }
    }
    """)
  end

  describe "generated shape" do
    test "the result struct exposes both data and errors fields" do
      assert %Result{data: nil, errors: []} = struct(Result)
    end
  end

  describe "loaded response" do
    test "partial data decodes even when the response carries field errors" do
      result = fetch(partial_data_with_errors())

      assert %Client.GetUser.Result.User{id: "u1", name: "Alice", email: nil, role: :admin} =
               result.data.user
    end

    test "field errors arrive as Error structs with message, path, locations, and extensions" do
      result = fetch(partial_data_with_errors())

      assert [
               %Error{
                 message: "Cannot resolve email",
                 path: ["user", "email"],
                 locations: [%{"line" => 5, "column" => 5}],
                 extensions: %{"code" => "INTERNAL_ERROR"}
               }
             ] = result.errors
    end

    test "an error without path, locations, or extensions decodes those fields as nil" do
      result =
        fetch(%{
          "data" => %{"user" => nil},
          "errors" => [%{"message" => "Something went wrong"}]
        })

      assert [
               %Error{
                 message: "Something went wrong",
                 path: nil,
                 locations: nil,
                 extensions: nil
               }
             ] = result.errors
    end

    test "null data with errors still returns ok, keeping data nil and all errors present" do
      result =
        fetch(%{
          "data" => nil,
          "errors" => [
            %{"message" => "Unauthorized", "extensions" => %{"code" => "UNAUTHORIZED"}},
            %{"message" => "Rate limited", "extensions" => %{"code" => "RATE_LIMITED"}}
          ]
        })

      assert result.data == nil
      assert [%Error{message: "Unauthorized"}, %Error{message: "Rate limited"}] = result.errors
    end

    test "a clean response leaves errors as an empty list" do
      result =
        fetch(%{
          "data" => %{
            "user" => %{
              "id" => "u1",
              "name" => "Alice",
              "email" => "a@example.com",
              "role" => "ADMIN"
            }
          }
        })

      assert result.errors == []
    end
  end

  defp fetch(response_body) do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, response_body)
    end)

    assert {:ok, %Result{} = result} = call()
    result
  end

  defp partial_data_with_errors do
    %{
      "data" => %{
        "user" => %{"id" => "u1", "name" => "Alice", "email" => nil, "role" => "ADMIN"}
      },
      "errors" => [
        %{
          "message" => "Cannot resolve email",
          "path" => ["user", "email"],
          "locations" => [%{"line" => 5, "column" => 5}],
          "extensions" => %{"code" => "INTERNAL_ERROR"}
        }
      ]
    }
  end

  defp call do
    Client.get_user(%{id: "u1"})
  end
end
