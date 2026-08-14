defmodule TypedGql.Integration.QueryWithAliasedRootFieldAndSkipIncludeDirectivesTest do
  # Integration suite: one document per file, one observable behavior per
  # test. Theme here: an aliased root field combined with @include/@skip on
  # scalar fields, checked across generated shape, dumped request, and
  # loaded response.
  use TypedGql.IntegrationCase, async: true

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql",
      req_options: [
        plug:
          {Req.Test,
           TypedGql.Integration.QueryWithAliasedRootFieldAndSkipIncludeDirectivesTest.Client}
      ]

    defgql(:owner_profile, """
    query OwnerProfile($id: ID!, $withEmail: Boolean!, $skipBio: Boolean!) {
      owner: user(id: $id) {
        id
        name
        email @include(if: $withEmail)
        role
        createdAt
        profile {
          bio @skip(if: $skipBio)
          avatarUrl
        }
      }
    }
    """)
  end

  describe "generated shape" do
    test "the aliased root field names the struct field and module after the alias" do
      assert Client.OwnerProfile.Result.__schema__(:fields) == [:owner]

      assert %{related: Client.OwnerProfile.Result.Owner, cardinality: :one} =
               Client.OwnerProfile.Result.__schema__(:embed, :owner)
    end

    test "enum and DateTime fields map to their custom Ecto types" do
      owner_mod = Client.OwnerProfile.Result.Owner

      assert {:parameterized, {TypedGql.Types.Enum, %{original_to_atom: roles}}} =
               owner_mod.__schema__(:type, :role)

      assert roles == %{"ADMIN" => :admin, "USER" => :user, "GUEST" => :guest}
      assert owner_mod.__schema__(:type, :created_at) == TypedGql.Types.DateTime
    end

    test "every operation variable becomes a snake_case Variables field" do
      assert Enum.sort(Client.OwnerProfile.Variables.__schema__(:fields)) ==
               [:id, :skip_bio, :with_email]
    end
  end

  describe "dumped request" do
    test "the printed document keeps the alias and both directives" do
      request = capture_request()

      assert request["operationName"] == "OwnerProfile"
      assert request["query"] =~ "owner: user(id: $id)"
      assert request["query"] =~ "email @include(if: $withEmail)"
      assert request["query"] =~ "bio @skip(if: $skipBio)"
    end

    test "variables serialize to camelCase JSON" do
      request = capture_request()

      assert request["variables"] == %{"id" => "u1", "withEmail" => true, "skipBio" => true}
    end
  end

  describe "loaded response" do
    test "an included field decodes and a server-skipped field falls back to nil" do
      result = fetch_owner()

      assert result.data.owner.email == "alice@example.com"
      assert result.data.owner.profile.bio == nil
      assert result.data.owner.profile.avatar_url == "https://img.example.com/a.png"
    end

    test "enum casts to its atom and DateTime to a %DateTime{}" do
      result = fetch_owner()

      assert %Client.OwnerProfile.Result.Owner{
               role: :admin,
               created_at: ~U[2025-01-15 10:30:00Z]
             } = result.data.owner
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

  defp fetch_owner do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "owner" => %{
            "id" => "u1",
            "name" => "Alice",
            "email" => "alice@example.com",
            "role" => "ADMIN",
            "createdAt" => "2025-01-15T10:30:00Z",
            "profile" => %{"avatarUrl" => "https://img.example.com/a.png"}
          }
        }
      })
    end)

    assert {:ok, %Result{} = result} = call()
    result
  end

  defp call do
    Client.owner_profile(%{id: "u1", with_email: true, skip_bio: true})
  end
end
