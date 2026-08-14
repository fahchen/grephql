defmodule TypedGql.Integration.QueryWithSkipIncludeDirectivesOnFragmentSpreadsTest do
  # Integration suite: one document per file, one observable behavior per
  # test. Theme here: @include on a fragment spread and @skip on an inline
  # fragment (directives on selections, not fields). Their nullability only
  # shows in the generated @type (`| nil`), which is unreadable for modules
  # compiled inside a test file (mix test disables debug_info at runtime),
  # so shape tests pin the flattened struct and decode tests pin the
  # nil-when-skipped behavior.
  use ExUnit.Case, async: true

  alias TypedGql.Result

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql"

    defgql(:conditional_spreads, """
    query ConditionalSpreads($id: ID!, $withDetails: Boolean!, $skipProfile: Boolean!) {
      user(id: $id) {
        id
        ...Details @include(if: $withDetails)
        ... on User @skip(if: $skipProfile) {
          profile { bio avatarUrl }
        }
      }
    }
    fragment Details on User { email role }
    """)
  end

  setup {Req.Test, :verify_on_exit!}

  describe "generated shape" do
    test "fields reached only through the conditional spread and inline fragment flatten into the User struct" do
      assert Client.ConditionalSpreads.Result.User.__schema__(:fields) ==
               [:id, :email, :role, :profile]
    end

    test "the inline fragment's profile becomes an embeds_one whose struct default is nil" do
      user_mod = Client.ConditionalSpreads.Result.User

      assert %{related: Client.ConditionalSpreads.Result.User.Profile, cardinality: :one} =
               user_mod.__schema__(:embed, :profile)

      assert user_mod.__struct__().profile == nil
    end
  end

  describe "dumped request" do
    test "the printed document keeps @include on the fragment spread and @skip on the inline fragment" do
      request = capture_request()

      assert request["operationName"] == "ConditionalSpreads"
      assert request["query"] =~ "...Details @include(if: $withDetails)"
      assert request["query"] =~ "... on User @skip(if: $skipProfile)"
      assert request["query"] =~ "fragment Details on User"
    end

    test "both directive control variables reach the variables JSON" do
      request = capture_request()

      assert request["variables"] ==
               %{"id" => "u1", "withDetails" => true, "skipProfile" => false}
    end
  end

  describe "loaded response" do
    test "when the server skips both fragments, email, role, and profile all decode as nil" do
      result = fetch(%{"id" => "u1"})

      assert %Client.ConditionalSpreads.Result.User{
               id: "u1",
               email: nil,
               role: nil,
               profile: nil
             } = result.data.user
    end

    test "when the server includes both fragments, their fields decode normally" do
      result =
        fetch(%{
          "id" => "u1",
          "email" => "alice@example.com",
          "role" => "ADMIN",
          "profile" => %{"bio" => "hi", "avatarUrl" => "https://img.example.com/a.png"}
        })

      assert %Client.ConditionalSpreads.Result.User{
               email: "alice@example.com",
               role: :admin,
               profile: %Client.ConditionalSpreads.Result.User.Profile{
                 bio: "hi",
                 avatar_url: "https://img.example.com/a.png"
               }
             } = result.data.user
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

  defp fetch(user) do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{"data" => %{"user" => user}})
    end)

    assert {:ok, %Result{} = result} = call()
    result
  end

  defp call do
    Client.conditional_spreads(
      %{id: "u1", with_details: true, skip_profile: false},
      req_options: [plug: {Req.Test, Client}]
    )
  end
end
