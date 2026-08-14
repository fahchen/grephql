defmodule TypedGql.Integration.GithubSchemaMutationCreateIssueInputObjectDumpTest do
  # Integration suite realism layer: one document against the real GitHub
  # schema (a pinned copy under test/support/schemas — TypedGql caches the
  # parsed schema per source path, so per-file clients parse it only once
  # per compile). Theme here: a real mutation whose CreateIssueInput input
  # object exercises snake_case field generation and camelCase dumping.
  use TypedGql.IntegrationCase, async: true

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/github.json",
      endpoint: "https://api.github.com/graphql",
      req_options: [
        plug:
          {Req.Test,
           TypedGql.Integration.GithubSchemaMutationCreateIssueInputObjectDumpTest.Client}
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

    defgql(:create_issue, ~GQL"""
    mutation CreateIssue($input: CreateIssueInput!) {
      createIssue(input: $input) {
        issue {
          id
          number
          title
          state
          createdAt
          author {
            login
          }
        }
      }
    }
    """)
  end

  describe "generated shape" do
    test "Variables embeds the generated CreateIssueInput module" do
      assert %{related: Client.Inputs.CreateIssueInput, cardinality: :one} =
               Client.CreateIssue.Variables.__schema__(:embed, :input)
    end

    test "the input module exposes snake_case fields for camelCase schema fields" do
      fields = Client.Inputs.CreateIssueInput.__schema__(:fields)

      assert :repository_id in fields
      assert :title in fields
    end
  end

  describe "dumped request" do
    test "input fields dump to camelCase JSON keys" do
      request = capture_request()

      assert request["operationName"] == "CreateIssue"

      assert %{
               "repositoryId" => "R_1",
               "title" => "Bug",
               "body" => "It crashes on startup"
             } = request["variables"]["input"]
    end

    test "no snake_case key leaks into the dumped input" do
      request = capture_request()

      refute request["variables"]["input"]
             |> Map.keys()
             |> Enum.any?(&String.contains?(&1, "_"))
    end

    test "omitted optional input fields are absent from the JSON, not null" do
      request = capture_request()

      assert Map.keys(request["variables"]["input"]) == ["body", "repositoryId", "title"]
    end

    test "a list of nested input objects dumps each element pruned to its given keys" do
      request =
        capture_request(%{
          input: %{
            repository_id: "R_1",
            title: "Bug",
            issue_fields: [
              %{field_id: "F_1", text_value: "high"},
              %{field_id: "F_2", delete: true}
            ]
          }
        })

      assert request["variables"]["input"]["issueFields"] == [
               %{"fieldId" => "F_1", "textValue" => "high"},
               %{"fieldId" => "F_2", "delete" => true}
             ]
    end
  end

  describe "loaded response" do
    test "the nested issue decodes with enum, DateTime, and nested author casts" do
      result = fetch()

      assert %Client.CreateIssue.Result.CreateIssue.Issue{
               id: "I_1",
               number: 42,
               title: "Bug",
               state: :open,
               created_at: ~U[2025-06-01 12:00:00Z],
               author: %{login: "octocat"}
             } = result.data.create_issue.issue
    end
  end

  defp capture_request(variables \\ nil) do
    parent = self()

    Req.Test.expect(Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:request, Jason.decode!(body)})
      Req.Test.json(conn, %{"data" => nil})
    end)

    assert {:ok, %Result{}} = if(variables, do: call(variables), else: call())
    assert_received {:request, request}
    request
  end

  defp fetch do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "createIssue" => %{
            "issue" => %{
              "id" => "I_1",
              "number" => 42,
              "title" => "Bug",
              "state" => "OPEN",
              "createdAt" => "2025-06-01T12:00:00Z",
              "author" => %{"login" => "octocat"}
            }
          }
        }
      })
    end)

    assert {:ok, %Result{} = result} = call()
    result
  end

  defp call do
    call(%{input: %{repository_id: "R_1", title: "Bug", body: "It crashes on startup"}})
  end

  defp call(variables) do
    Client.create_issue(variables)
  end
end
