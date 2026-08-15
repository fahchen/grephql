defmodule TypedGql.Integration.CustomScalarMappingOverridingABuiltinTest do
  @moduledoc """
  The `:scalars` option, and which `Ecto.Type` callbacks it puts on the path.
  Pins what `guides/mapping-custom-scalars.md` tells users:

  - a mapping for a name that already has a built-in replaces it
  - the default `embed_as: :self` routes both directions through `cast/1`,
    leaving `dump/1` and `load/1` unused
  - declaring `embed_as: :dump` routes the request through `dump/1` and the
    response through `load/1` instead
  - a scalar the schema uses with no mapping at all fails the build
  """
  use TypedGql.IntegrationCase, async: true

  defmodule SelfScalar do
    @moduledoc false
    use Ecto.Type

    def type, do: :string
    def cast(value) when is_binary(value), do: {:ok, "cast:" <> value}
    def cast(_other), do: :error
    def dump(value) when is_binary(value), do: {:ok, "dump:" <> value}
    def dump(_other), do: :error
    def load(value) when is_binary(value), do: {:ok, "load:" <> value}
    def load(_other), do: :error
  end

  defmodule DumpScalar do
    @moduledoc false
    use Ecto.Type

    def type, do: :string
    def cast(value) when is_binary(value), do: {:ok, "cast:" <> value}
    def cast(_other), do: :error
    def dump(value) when is_binary(value), do: {:ok, "dump:" <> value}
    def dump(_other), do: :error
    def load(value) when is_binary(value), do: {:ok, "load:" <> value}
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
      "mutation P($input: CreatePostInput!) { createPost(input: $input) { id } }"
    )
  end

  describe "generated shape" do
    test "the configured module replaces the built-in mapping for that scalar" do
      assert SelfClient.GetUser.Result.User.__schema__(:type, :created_at) == SelfScalar
    end
  end

  describe "loaded response" do
    test "the default embed_as routes the response through cast/1, not load/1" do
      Req.Test.expect(SelfClient, fn conn ->
        Req.Test.json(conn, %{"data" => %{"user" => %{"id" => "u1", "createdAt" => "X"}}})
      end)

      assert {:ok, %Result{} = result} = SelfClient.get_user(%{id: "u1"})
      assert result.data.user.created_at == "cast:X"
    end

    test "embed_as :dump routes the response through load/1" do
      Req.Test.expect(DumpClient, fn conn ->
        Req.Test.json(conn, %{"data" => nil})
      end)

      assert {:ok, %Result{}} =
               DumpClient.create_post(%{
                 input: %{title: "T", tags: [], metadata: %{publish_at: "X"}}
               })
    end
  end

  describe "dumped request" do
    test "the default embed_as sends the cast value, without calling dump/1" do
      parent = self()

      Req.Test.expect(DumpClient, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(parent, {:request, Jason.decode!(body)})
        Req.Test.json(conn, %{"data" => nil})
      end)

      assert {:ok, %Result{}} =
               DumpClient.create_post(%{
                 input: %{title: "T", tags: [], metadata: %{publish_at: "X"}}
               })

      assert_received {:request, request}

      # DumpScalar declares embed_as: :dump, so the value cast on the way in is
      # dumped again for the wire.
      assert request["variables"]["input"]["metadata"]["publishAt"] == "dump:cast:X"
    end
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
