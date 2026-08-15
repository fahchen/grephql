defmodule TypedGql.Integration.GithubSchemaRepositoryQueryWithConnectionsEnumsAndNullableNodesTest do
  @moduledoc """
  Relay connection pagination against the real GitHub schema, and the null shapes
  GitHub actually returns:

  - a connection's `nodes` is a plain array field, since `[Issue]` is nullable throughout
  - the URI custom scalar maps to `:string` and DateTime to the custom Ecto type
  - the `IssueState` enum carries exactly the states the schema defines
  - connection arguments and the enum literal survive printing
  - a nested connection decodes with DateTime and enum casts
  - a null connection node and a null author (deleted account) survive the cast
  """
  use TypedGql.IntegrationCase, async: true

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/github.json",
      endpoint: "https://api.github.com/graphql",
      req_options: [
        plug: {Req.Test, __MODULE__}
      ],
      scalars: %{
        # GitHub-specific scalars not covered by builtins
        "GitObjectID" => :string,
        "GitRefname" => :string,
        "GitSSHRemote" => :string,
        "GitTimestamp" => :string,
        "PreciseDateTime" => :string,
        "X509Certificate" => :string,
        "CustomPropertyValue" => :string,
        "_Any" => :string
      }

    defgql(:repository_overview, ~GQL"""
    query RepositoryOverview($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        name
        description
        url
        createdAt
        stargazerCount
        isPrivate
        owner {
          login
          avatarUrl
        }
        issues(first: 10, states: [OPEN]) {
          totalCount
          nodes {
            title
            number
            state
            createdAt
            author {
              login
            }
            labels(first: 5) {
              nodes {
                name
                color
              }
            }
          }
        }
      }
    }
    """)
  end

  describe "generated shape" do
    test "connection nodes is a plain array field because [Issue] is nullable throughout" do
      issues_mod = Client.RepositoryOverview.Result.Repository.Issues
      issue_mod = Client.RepositoryOverview.Result.Repository.Issues.Nodes

      assert issues_mod.__schema__(:embeds) == []

      assert {:array, {:parameterized, {Ecto.Embedded, %{related: ^issue_mod}}}} =
               issues_mod.__schema__(:type, :nodes)
    end

    test "the URI custom scalar maps to :string and DateTime to the custom Ecto type" do
      repo_mod = Client.RepositoryOverview.Result.Repository

      assert repo_mod.__schema__(:type, :url) == :string
      assert repo_mod.__schema__(:type, :created_at) == TypedGql.Types.DateTime
    end

    test "the IssueState enum carries exactly the states the schema defines" do
      assert {:parameterized, {TypedGql.Types.Enum, %{original_to_atom: states}}} =
               Client.RepositoryOverview.Result.Repository.Issues.Nodes.__schema__(:type, :state)

      assert states == %{"OPEN" => :open, "CLOSED" => :closed}
    end
  end

  describe "dumped request" do
    test "connection arguments and the enum literal survive printing" do
      request = capture_request()

      assert request["operationName"] == "RepositoryOverview"
      assert request["query"] =~ "issues(first: 10, states: [OPEN])"
      assert request["query"] =~ "labels(first: 5)"
    end

    test "variables serialize as plain JSON strings" do
      request = capture_request()

      assert request["variables"] == %{"owner" => "elixir-lang", "name" => "elixir"}
    end
  end

  describe "loaded response" do
    test "a nested connection decodes with DateTime and enum casts" do
      result = fetch()

      assert %Client.RepositoryOverview.Result.Repository{
               name: "elixir",
               description: nil,
               url: "https://github.com/elixir-lang/elixir",
               created_at: ~U[2011-01-09 22:44:31Z],
               stargazer_count: 25_000,
               is_private: false,
               owner: %Client.RepositoryOverview.Result.Repository.Owner{login: "elixir-lang"}
             } = result.data.repository

      assert %Client.RepositoryOverview.Result.Repository.Issues.Nodes{
               state: :open,
               created_at: ~U[2025-05-01 09:00:00Z],
               author: %Client.RepositoryOverview.Result.Repository.Issues.Nodes.Author{
                 login: "josevalim"
               },
               labels: %Client.RepositoryOverview.Result.Repository.Issues.Nodes.Labels{
                 nodes: [
                   %Client.RepositoryOverview.Result.Repository.Issues.Nodes.Labels.Nodes{
                     name: "Kind:Bug"
                   },
                   %Client.RepositoryOverview.Result.Repository.Issues.Nodes.Labels.Nodes{
                     name: "Area:Compiler"
                   }
                 ]
               }
             } = hd(result.data.repository.issues.nodes)
    end

    test "a null connection node and a null author (deleted account) survive the cast" do
      result = fetch()

      assert [_first, nil, orphan] = result.data.repository.issues.nodes

      assert %Client.RepositoryOverview.Result.Repository.Issues.Nodes{
               number: 14_002,
               author: nil,
               labels: %Client.RepositoryOverview.Result.Repository.Issues.Nodes.Labels{nodes: []}
             } = orphan
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

  defp fetch do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "repository" => %{
            "name" => "elixir",
            "description" => nil,
            "url" => "https://github.com/elixir-lang/elixir",
            "createdAt" => "2011-01-09T22:44:31Z",
            "stargazerCount" => 25_000,
            "isPrivate" => false,
            "owner" => %{
              "login" => "elixir-lang",
              "avatarUrl" => "https://avatars.githubusercontent.com/u/1481354"
            },
            "issues" => %{
              "totalCount" => 2,
              "nodes" => [
                %{
                  "title" => "Compiler warning on nested case",
                  "number" => 14_001,
                  "state" => "OPEN",
                  "createdAt" => "2025-05-01T09:00:00Z",
                  "author" => %{"login" => "josevalim"},
                  "labels" => %{
                    "nodes" => [
                      %{"name" => "Kind:Bug", "color" => "d73a4a"},
                      %{"name" => "Area:Compiler", "color" => "0075ca"}
                    ]
                  }
                },
                nil,
                %{
                  "title" => "Docs typo",
                  "number" => 14_002,
                  "state" => "OPEN",
                  "createdAt" => "2025-05-02T10:00:00Z",
                  "author" => nil,
                  "labels" => %{"nodes" => []}
                }
              ]
            }
          }
        }
      })
    end)

    assert {:ok, %Result{} = result} = call()
    result
  end

  defp call do
    Client.repository_overview(%{owner: "elixir-lang", name: "elixir"})
  end
end
