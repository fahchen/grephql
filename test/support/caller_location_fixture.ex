defmodule TypedGql.Test.CallerLocationFixture do
  @moduledoc false
  # Generated modules should point at the `defgql` that asked for them, not at
  # wherever inside typed_gql they were created. Each operation below records
  # its own line so a test can assert the line as well as the file, and stay
  # correct when this file is edited.
  use TypedGql,
    otp_app: :typed_gql,
    source: "schemas/integration.json",
    endpoint: "https://api.example.com/graphql"

  @result_line __ENV__.line + 1
  defgql(:get_user, """
  query GetUser($id: ID!) {
    user(id: $id) {
      id
      name
    }
  }
  """)

  @union_line __ENV__.line + 1
  defgql(:search, """
  query Search($term: String!) {
    search(query: $term) {
      __typename
      ... on User { name }
      ... on Post { title }
    }
  }
  """)

  @input_line __ENV__.line + 1
  defgql(:create_post, """
  mutation CreatePost($input: CreatePostInput!) {
    createPost(input: $input) {
      id
    }
  }
  """)

  @fragment_line __ENV__.line + 1
  deffragment("""
  fragment UserFields on User {
    id
    email
  }
  """)

  @doc "The line each operation was declared on, by the module it generates."
  @spec lines() :: %{module() => pos_integer()}
  def lines do
    %{
      __MODULE__.GetUser.Result => @result_line,
      __MODULE__.GetUser.Result.User => @result_line,
      __MODULE__.GetUser.Variables => @result_line,
      __MODULE__.Search.Result.Search.Union => @union_line,
      __MODULE__.Search.Result.Search.User => @union_line,
      __MODULE__.Inputs.CreatePostInput => @input_line,
      __MODULE__.Fragments.UserFields => @fragment_line
    }
  end
end
