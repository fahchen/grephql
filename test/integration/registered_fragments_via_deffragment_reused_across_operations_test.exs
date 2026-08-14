defmodule TypedGql.Integration.RegisteredFragmentsViaDeffragmentReusedAcrossOperationsTest do
  @moduledoc """
  The `deffragment` workflow — fragments registered once on the client, one
  spreading the other, reused from two operations:

  - each operation generates its own Result module
  - a registered fragment generates its own struct under `Client.Fragments`
  - the fragment spreading another embeds the nested selection
  - fields reached only through a spread land on the operation's struct
  - each printed document appends exactly the fragments it needs, each one once
  - fields and nested objects reached through spreads decode into the Result struct
  """
  use TypedGql.IntegrationCase, async: true

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql",
      req_options: [
        plug:
          {Req.Test,
           TypedGql.Integration.RegisteredFragmentsViaDeffragmentReusedAcrossOperationsTest.Client}
      ]

    deffragment("fragment UserCore on User { id name role }")

    deffragment("fragment PostDetail on Post { id title status author { ...UserCore } }")

    defgql(:get_user, """
    query GetUser($id: ID!) {
      user(id: $id) {
        ...UserCore
        email
      }
    }
    """)

    defgql(:list_drafts, """
    query ListDrafts {
      drafts {
        ...PostDetail
      }
    }
    """)
  end

  describe "generated shape" do
    test "each operation generates its own Result module" do
      assert Client.GetUser.Result.__schema__(:fields) == [:user]
      assert Client.ListDrafts.Result.__schema__(:fields) == [:drafts]
    end

    test "a registered fragment generates its own struct under Client.Fragments" do
      assert Code.ensure_loaded?(Client.Fragments.UserCore)
      assert Client.Fragments.UserCore.__schema__(:fields) == [:id, :name, :role]
    end

    test "the fragment spreading another fragment embeds the nested selection" do
      assert Client.Fragments.PostDetail.__schema__(:fields) == [:id, :title, :status, :author]

      assert %{related: Client.Fragments.PostDetail.Author, cardinality: :one} =
               Client.Fragments.PostDetail.__schema__(:embed, :author)
    end

    test "fields reached only through a spread land on the operation's struct" do
      assert Enum.sort(Client.GetUser.Result.User.__schema__(:fields)) ==
               [:email, :id, :name, :role]
    end
  end

  describe "dumped request" do
    test "the GetUser document appends only the UserCore fragment source" do
      request = capture_request(&call_get_user/0)

      assert request["operationName"] == "GetUser"
      assert [_only_spread_use] = :binary.matches(request["query"], "fragment UserCore on User")
      refute request["query"] =~ "fragment PostDetail"
    end

    test "the ListDrafts document appends PostDetail and transitively UserCore, each once" do
      request = capture_request(&call_list_drafts/0)

      assert request["operationName"] == "ListDrafts"
      assert [_post_detail] = :binary.matches(request["query"], "fragment PostDetail on Post")
      assert [_user_core] = :binary.matches(request["query"], "fragment UserCore on User")
    end
  end

  describe "loaded response" do
    test "fields reached only through the UserCore spread decode into the Result struct" do
      result = fetch_user()

      assert %Client.GetUser.Result.User{
               id: "u1",
               name: "Alice",
               role: :admin,
               email: "alice@example.com"
             } = result.data.user
    end

    test "the nested spread decodes the author object inside each draft" do
      result = fetch_drafts()

      assert [%{id: "p1", title: "Draft post", status: :draft, author: author}] =
               result.data.drafts

      assert %{id: "u1", name: "Alice", role: :admin} = author
    end
  end

  defp capture_request(call) do
    parent = self()

    Req.Test.expect(Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:request, Jason.decode!(body)})
      Req.Test.json(conn, %{"data" => nil})
    end)

    assert {:ok, %Result{}} = call.()
    assert_received {:request, request}
    request
  end

  defp fetch_user do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "user" => %{
            "id" => "u1",
            "name" => "Alice",
            "role" => "ADMIN",
            "email" => "alice@example.com"
          }
        }
      })
    end)

    assert {:ok, %Result{} = result} = call_get_user()
    result
  end

  defp fetch_drafts do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "drafts" => [
            %{
              "id" => "p1",
              "title" => "Draft post",
              "status" => "DRAFT",
              "author" => %{"id" => "u1", "name" => "Alice", "role" => "ADMIN"}
            }
          ]
        }
      })
    end)

    assert {:ok, %Result{} = result} = call_list_drafts()
    result
  end

  defp call_get_user do
    Client.get_user(%{id: "u1"})
  end

  defp call_list_drafts do
    Client.list_drafts()
  end
end
