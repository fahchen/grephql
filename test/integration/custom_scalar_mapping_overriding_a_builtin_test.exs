defmodule TypedGql.Integration.CustomScalarMappingOverridingABuiltinTest do
  @moduledoc """
  The `:scalars` option, and which `Ecto.Type` callbacks it puts on the path.
  Pins what `guides/mapping-custom-scalars.md` tells users:

  - a mapping for a name that already has a built-in replaces it
  - under `embed_as: :dump`, a variable crosses `cast/1` then `dump/1`, and a
    response value crosses `load/1` alone — the request path runs two
    callbacks, the response path one
  - under the default `embed_as: :self`, both directions run `cast/1` and the
    `dump/1` and `load/1` that `Ecto.Type` requires are never called
  - a scalar the schema uses with no mapping at all fails the build

  The types below mark each callback they pass through, so the nesting of the
  markers in an asserted value is the order the callbacks ran in.
  """
  use TypedGql.IntegrationCase, async: true

  defmodule SelfScalar do
    @moduledoc false
    use Ecto.Type

    def type, do: :string
    def cast(value) when is_binary(value), do: {:ok, "C(" <> value <> ")"}
    def cast(_other), do: :error
    def dump(value) when is_binary(value), do: {:ok, "D(" <> value <> ")"}
    def dump(_other), do: :error
    def load(value) when is_binary(value), do: {:ok, "L(" <> value <> ")"}
    def load(_other), do: :error
  end

  defmodule DumpScalar do
    @moduledoc false
    use Ecto.Type

    def type, do: :string
    def cast(value) when is_binary(value), do: {:ok, "C(" <> value <> ")"}
    def cast(_other), do: :error
    def dump(value) when is_binary(value), do: {:ok, "D(" <> value <> ")"}
    def dump(_other), do: :error
    def load(value) when is_binary(value), do: {:ok, "L(" <> value <> ")"}
    def load(_other), do: :error
    def embed_as(_format), do: :dump
  end

  defmodule SelfClient do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql",
      req_options: [plug: {Req.Test, __MODULE__}],
      scalars: %{
        "DateTime" => TypedGql.Integration.CustomScalarMappingOverridingABuiltinTest.SelfScalar
      }

    defgql(:get_user, "query GetUser($id: ID!) { user(id: $id) { id createdAt } }")

    defgql(
      :create_post,
      "mutation P($input: CreatePostInput!) { createPost(input: $input) { id } }"
    )
  end

  defmodule DumpClient do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/integration.json",
      endpoint: "https://api.example.com/graphql",
      req_options: [plug: {Req.Test, __MODULE__}],
      scalars: %{
        "DateTime" => TypedGql.Integration.CustomScalarMappingOverridingABuiltinTest.DumpScalar
      }

    defgql(
      :create_post,
      "mutation P($input: CreatePostInput!) { createPost(input: $input) { id publishedAt } }"
    )
  end

  describe "generated shape" do
    test "the configured module replaces the built-in mapping for that scalar" do
      assert SelfClient.GetUser.Result.User.__schema__(:type, :created_at) == SelfScalar
    end
  end

  describe "embed_as :dump — one callback per crossing" do
    test "a variable crosses cast/1 and then dump/1, in that order" do
      request = capture_dump_request()

      assert request["variables"]["input"]["metadata"]["publishAt"] == "D(C(raw))"
    end

    test "a response value crosses load/1 alone" do
      Req.Test.expect(DumpClient, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{"createPost" => %{"id" => "p1", "publishedAt" => "srv"}}
        })
      end)

      assert {:ok, %Result{} = result} = create_post(DumpClient)

      # No C( ) around it: cast/1 does not run on the way back.
      assert result.data.create_post.published_at == "L(srv)"
    end
  end

  describe "embed_as :self — cast/1 does all of it" do
    test "the response runs cast/1, not load/1" do
      Req.Test.expect(SelfClient, fn conn ->
        Req.Test.json(conn, %{"data" => %{"user" => %{"id" => "u1", "createdAt" => "srv"}}})
      end)

      assert {:ok, %Result{} = result} = SelfClient.get_user(%{id: "u1"})
      assert result.data.user.created_at == "C(srv)"
    end

    test "the request sends what cast/1 returned, without running dump/1" do
      parent = self()

      Req.Test.expect(SelfClient, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(parent, {:request, Jason.decode!(body)})
        Req.Test.json(conn, %{"data" => nil})
      end)

      assert {:ok, %Result{}} = create_post(SelfClient)
      assert_received {:request, request}

      # No D( ) around it: the cast value goes to the JSON encoder untouched.
      assert request["variables"]["input"]["metadata"]["publishAt"] == "C(raw)"
    end
  end

  defp capture_dump_request do
    parent = self()

    Req.Test.expect(DumpClient, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:request, Jason.decode!(body)})
      Req.Test.json(conn, %{"data" => nil})
    end)

    assert {:ok, %Result{}} = create_post(DumpClient)
    assert_received {:request, request}
    request
  end

  defp create_post(client) do
    client.create_post(%{input: %{title: "T", tags: [], metadata: %{publish_at: "raw"}}})
  end

  describe "compile errors" do
    # Repository.sshUrl is a GitSSHRemote, which no built-in covers.
    test "a scalar with no built-in and no mapping fails the build" do
      error =
        assert_raise CompileError, fn ->
          Code.compile_string("""
          defmodule TypedGql.Test.UnmappedScalarClient do
            use TypedGql,
              otp_app: :typed_gql,
              source: "test/support/schemas/github.json"

            defgql(:ssh_url, "query SshUrl($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { sshUrl } }")
          end
          """)
        end

      assert error.description =~ "unknown scalar type"
    end
  end
end
