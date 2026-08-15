defmodule TypedGql.Integration.MalformedServerDataEnumTypenameAndTypeMismatchHandlingTest do
  @moduledoc """
  A server that violates its own schema. Data Ecto cannot load surfaces as
  `{:error, %TypedGql.DecodeError{}}`; shape violations Ecto tolerates load leniently.

  Reported as a DecodeError:

  - a union element whose `__typename` is unknown, or missing entirely
  - an enum value outside the schema
  - a scalar of the wrong JSON type

  Tolerated on load:

  - a non-null root list sent as null, and a root field missing from the data map
  - a null element inside a list of non-null union members
  - an enum value differing from the schema only in case
  - fields the server sends beyond the selection
  """
  use TypedGql.IntegrationCase, async: true

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql",
      req_options: [
        plug: {Req.Test, __MODULE__}
      ]

    defgql(:search, """
    query Search($term: String!) {
      search(query: $term) {
        ... on User {
          id
          name
          role
        }
        ... on Post {
          id
          title
          status
        }
      }
    }
    """)
  end

  describe "malformed server data" do
    test "a non-null root list sent as null loads as nil instead of erroring" do
      # Documents current contract: the schema's [SearchResult!]! is not
      # enforced on load; a null root field simply becomes nil.
      result = fetch(%{"search" => nil})

      assert result.data.search == nil
    end

    test "a root field missing from the data map loads as nil" do
      # Documents current contract: an absent key is treated like an
      # explicit null rather than a decode error.
      result = fetch(%{})

      assert result.data.search == nil
    end

    test "a null element inside a list of non-null union members survives as nil" do
      # Documents current contract: element non-nullability is not enforced;
      # the nil passes through untouched.
      result = fetch(%{"search" => [nil]})

      assert result.data.search == [nil]
    end

    test "an enum value differing only in case still casts to its atom" do
      # Documents current contract: enum loading is case-insensitive, so a
      # server sending "admin" instead of "ADMIN" is tolerated.
      result = fetch(%{"search" => [user_payload("admin")]})

      assert [%Client.Search.Result.Search.User{role: :admin}] = result.data.search
    end

    test "fields the server sends beyond the selection are silently dropped" do
      # Documents current contract: unselected and unknown keys are ignored;
      # only the selected fields land on the struct.
      payload =
        Map.merge(user_payload("ADMIN"), %{"email" => "alice@example.com", "unknownField" => 42})

      result = fetch(%{"search" => [payload]})

      assert [%Client.Search.Result.Search.User{id: "u1", name: "Alice", role: :admin}] =
               result.data.search
    end

    test "a union element with an unknown __typename returns a DecodeError" do
      error = fetch_error(%{"search" => [%{"__typename" => "Robot", "id" => "r1"}]})

      assert Exception.message(error) =~ "cannot decode response data"
    end

    test "a union element missing __typename returns a DecodeError" do
      assert %TypedGql.DecodeError{} = fetch_error(%{"search" => [%{"id" => "u1"}]})
    end

    test "an enum value outside the schema returns a DecodeError" do
      assert %TypedGql.DecodeError{} = fetch_error(%{"search" => [user_payload("SUPERADMIN")]})
    end

    test "a scalar of the wrong JSON type returns a DecodeError" do
      payload = %{user_payload("ADMIN") | "id" => 123}

      assert %TypedGql.DecodeError{} = fetch_error(%{"search" => [payload]})
    end
  end

  defp fetch(data) do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{"data" => data})
    end)

    assert {:ok, %Result{} = result} = call()
    result
  end

  defp fetch_error(data) do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{"data" => data})
    end)

    assert {:error, %TypedGql.DecodeError{} = error} = call()
    error
  end

  defp user_payload(role) do
    %{"__typename" => "User", "id" => "u1", "name" => "Alice", "role" => role}
  end

  defp call do
    Client.search(%{term: "elixir"})
  end
end
