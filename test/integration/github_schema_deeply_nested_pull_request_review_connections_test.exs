defmodule TypedGql.Integration.GithubSchemaDeeplyNestedPullRequestReviewConnectionsTest do
  # Integration suite realism layer: one document against the real GitHub
  # schema (a pinned copy under test/support/schemas). Theme here: deep
  # connection-in-connection nesting — pull requests > reviews > commits >
  # statusCheckRollup — with the nullable chains GitHub really returns at
  # every level (null rollup before checks run, null review author for a
  # deleted account, empty review connections).
  use TypedGql.IntegrationCase, async: true

  defmodule Client do
    use TypedGql,
      otp_app: :typed_gql,
      source: "../support/schemas/github.json",
      endpoint: "https://api.github.com/graphql",
      req_options: [
        plug:
          {Req.Test,
           TypedGql.Integration.GithubSchemaDeeplyNestedPullRequestReviewConnectionsTest.Client}
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

    defgql(:pull_request_board, ~GQL"""
    query PullRequestBoard($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        pullRequests(first: 5, states: [OPEN]) {
          nodes {
            title
            number
            state
            author {
              login
            }
            reviews(first: 3) {
              nodes {
                state
                author {
                  login
                }
                body
              }
            }
            commits(last: 1) {
              nodes {
                commit {
                  message
                  statusCheckRollup {
                    state
                  }
                }
              }
            }
          }
        }
      }
    }
    """)
  end

  describe "generated shape" do
    test "module nesting mirrors the document down to the commit rollup" do
      pull_request_mod = Client.PullRequestBoard.Result.Repository.PullRequests.Nodes
      reviews_mod = Client.PullRequestBoard.Result.Repository.PullRequests.Nodes.Reviews
      review_mod = Client.PullRequestBoard.Result.Repository.PullRequests.Nodes.Reviews.Nodes

      commit_mod =
        Client.PullRequestBoard.Result.Repository.PullRequests.Nodes.Commits.Nodes.Commit

      assert %{related: ^reviews_mod, cardinality: :one} =
               pull_request_mod.__schema__(:embed, :reviews)

      assert {:array, {:parameterized, {Ecto.Embedded, %{related: ^review_mod}}}} =
               reviews_mod.__schema__(:type, :nodes)

      assert Enum.sort(review_mod.__schema__(:fields)) == [:author, :body, :state]

      assert %{related: ^commit_mod, cardinality: :one} =
               Client.PullRequestBoard.Result.Repository.PullRequests.Nodes.Commits.Nodes.__schema__(
                 :embed,
                 :commit
               )
    end

    test "the PullRequestReviewState enum carries the five review states" do
      assert {:parameterized, {TypedGql.Types.Enum, %{original_to_atom: states}}} =
               Client.PullRequestBoard.Result.Repository.PullRequests.Nodes.Reviews.Nodes.__schema__(
                 :type,
                 :state
               )

      assert states == %{
               "PENDING" => :pending,
               "COMMENTED" => :commented,
               "APPROVED" => :approved,
               "CHANGES_REQUESTED" => :changes_requested,
               "DISMISSED" => :dismissed
             }
    end

    test "the StatusState enum carries the five rollup states" do
      rollup_mod =
        Client.PullRequestBoard.Result.Repository.PullRequests.Nodes.Commits.Nodes.Commit.StatusCheckRollup

      assert {:parameterized, {TypedGql.Types.Enum, %{original_to_atom: states}}} =
               rollup_mod.__schema__(:type, :state)

      assert states == %{
               "EXPECTED" => :expected,
               "ERROR" => :error,
               "FAILURE" => :failure,
               "PENDING" => :pending,
               "SUCCESS" => :success
             }
    end
  end

  describe "dumped request" do
    test "both connection arguments survive printing" do
      request = capture_request()

      assert request["operationName"] == "PullRequestBoard"
      assert request["query"] =~ "pullRequests(first: 5, states: [OPEN])"
      assert request["query"] =~ "commits(last: 1)"
    end
  end

  describe "loaded response" do
    test "a full deep chain decodes review and rollup enums end to end" do
      result = fetch()

      assert %{
               title: "Speed up compiler",
               number: 501,
               state: :open,
               author: %{login: "josevalim"},
               reviews: %{nodes: [%{state: :approved, author: %{login: "ericmj"}} | _rest]},
               commits: %{
                 nodes: [
                   %{
                     commit: %{
                       message: "Cache beam files",
                       status_check_rollup: %{state: :success}
                     }
                   }
                 ]
               }
             } = hd(result.data.repository.pull_requests.nodes)
    end

    test "a pull request with no reviews decodes an empty nodes list" do
      result = fetch()

      assert [_reviewed, fresh] = result.data.repository.pull_requests.nodes
      assert fresh.reviews.nodes == []
    end

    test "a null statusCheckRollup (no checks run yet) survives as nil" do
      result = fetch()

      assert [_reviewed, fresh] = result.data.repository.pull_requests.nodes
      assert [%{commit: %{status_check_rollup: nil}}] = fresh.commits.nodes
    end

    test "a null review author (deleted account) survives as nil" do
      result = fetch()

      assert [reviewed, _fresh] = result.data.repository.pull_requests.nodes
      assert [_approved, %{state: :commented, author: nil}] = reviewed.reviews.nodes
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
            "pullRequests" => %{
              "nodes" => [
                %{
                  "title" => "Speed up compiler",
                  "number" => 501,
                  "state" => "OPEN",
                  "author" => %{"login" => "josevalim"},
                  "reviews" => %{
                    "nodes" => [
                      %{
                        "state" => "APPROVED",
                        "author" => %{"login" => "ericmj"},
                        "body" => "Ship it"
                      },
                      %{
                        "state" => "COMMENTED",
                        "author" => nil,
                        "body" => "Left some notes before deleting my account"
                      }
                    ]
                  },
                  "commits" => %{
                    "nodes" => [
                      %{
                        "commit" => %{
                          "message" => "Cache beam files",
                          "statusCheckRollup" => %{"state" => "SUCCESS"}
                        }
                      }
                    ]
                  }
                },
                %{
                  "title" => "Fix typo in docs",
                  "number" => 502,
                  "state" => "OPEN",
                  "author" => %{"login" => "whatyouhide"},
                  "reviews" => %{"nodes" => []},
                  "commits" => %{
                    "nodes" => [
                      %{
                        "commit" => %{
                          "message" => "Fix typo",
                          "statusCheckRollup" => nil
                        }
                      }
                    ]
                  }
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
    Client.pull_request_board(%{owner: "elixir-lang", name: "elixir"})
  end
end
