# Example: GitHub GraphQL API client
#
# Demonstrates using Grephql with the GitHub GraphQL schema (5.9MB).
# Covers nested objects, connections, input types, and mutations.
#
# Enums are auto-handled. Built-in scalars (DateTime, Date, URI, HTML,
# BigInt, Base64String) are auto-mapped. Only GitHub-specific custom
# scalars need explicit configuration.
#
# Usage: iex -S mix run examples/github_client.exs

defmodule Example.GitHubClient do
  use Grephql,
    otp_app: :grephql,
    source: "github_schema.json",
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

  # Query: nested objects, connections, pagination
  defgql(:get_repository, ~GQL"""
  query GetRepository($owner: String!, $name: String!) {
    repository(owner: $owner, name: $name) {
      name
      description
      url
      createdAt
      updatedAt
      stargazerCount
      forkCount
      isPrivate
      defaultBranchRef {
        name
        prefix
      }
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

  # Query: viewer profile (no variables)
  defgql(:get_viewer, ~GQL"""
  query GetViewer {
    viewer {
      login
      name
      email
      bio
      company
      avatarUrl
      createdAt
      followers {
        totalCount
      }
      following {
        totalCount
      }
      repositories(first: 5, orderBy: {field: UPDATED_AT, direction: DESC}) {
        nodes {
          name
          description
          url
          stargazerCount
        }
      }
    }
  }
  """)

  # Mutation: input object
  defgql(:create_issue, ~GQL"""
  mutation CreateIssue($input: CreateIssueInput!) {
    createIssue(input: $input) {
      issue {
        id
        number
        title
        body
        state
        createdAt
        author {
          login
        }
      }
    }
  }
  """)

  # Query: deeply nested connections
  defgql(:get_pull_requests, ~GQL"""
  query GetPullRequests($owner: String!, $name: String!) {
    repository(owner: $owner, name: $name) {
      pullRequests(first: 5, states: [OPEN]) {
        nodes {
          title
          number
          state
          author {
            login
          }
          headRefName
          baseRefName
          mergeable
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

IO.puts("Example.GitHubClient compiled successfully.")
IO.puts("  Queries: get_repository, get_viewer, create_issue, get_pull_requests")
