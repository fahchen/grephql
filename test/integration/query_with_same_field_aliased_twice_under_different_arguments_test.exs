defmodule TypedGql.Integration.QueryWithSameFieldAliasedTwiceUnderDifferentArgumentsTest do
  # Integration suite: one document per file, one observable behavior per
  # test. Theme here: the everyday pattern of selecting the same root field
  # twice under different aliases with different arguments — two response
  # keys, two independent selections, no merging between them.
  use ExUnit.Case, async: true

  alias TypedGql.Result

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql"

    defgql(:pair_of_users, """
    query PairOfUsers($first: ID!, $second: ID!) {
      author: user(id: $first) {
        id
        name
      }
      reviewer: user(id: $second) {
        id
        email
        role
      }
    }
    """)
  end

  setup {Req.Test, :verify_on_exit!}

  describe "generated shape" do
    test "each alias gets its own module with only its own selection" do
      assert Enum.sort(Client.PairOfUsers.Result.__schema__(:fields)) == [:author, :reviewer]

      assert Client.PairOfUsers.Result.Author.__schema__(:fields) == [:id, :name]

      assert Enum.sort(Client.PairOfUsers.Result.Reviewer.__schema__(:fields)) == [
               :email,
               :id,
               :role
             ]
    end
  end

  describe "dumped request" do
    test "both aliased copies of the field are printed with their own arguments" do
      request = capture_request()

      assert request["query"] =~ "author: user(id: $first)"
      assert request["query"] =~ "reviewer: user(id: $second)"
      assert request["variables"] == %{"first" => "u1", "second" => "u2"}
    end
  end

  describe "loaded response" do
    test "the two aliased keys decode independently into their own structs" do
      Req.Test.expect(Client, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "author" => %{"id" => "u1", "name" => "Alice"},
            "reviewer" => %{"id" => "u2", "email" => "bob@example.com", "role" => "USER"}
          }
        })
      end)

      assert {:ok, %Result{} = result} = call()

      assert %Client.PairOfUsers.Result.Author{id: "u1", name: "Alice"} = result.data.author

      assert %Client.PairOfUsers.Result.Reviewer{
               id: "u2",
               email: "bob@example.com",
               role: :user
             } = result.data.reviewer
    end
  end

  defp capture_request do
    parent = self()

    Req.Test.expect(Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:request, Jason.decode!(body)})
      Req.Test.json(conn, %{"data" => nil})
    end)

    assert {:ok, %Result{}} = call()
    assert_received {:request, request}
    request
  end

  defp call do
    Client.pair_of_users(
      %{first: "u1", second: "u2"},
      req_options: [plug: {Req.Test, Client}]
    )
  end
end
