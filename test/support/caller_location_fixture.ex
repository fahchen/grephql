defmodule TypedGql.Test.CallerLocationFixture do
  @moduledoc false
  # Generated modules should point at the `defgql` that asked for them, not at
  # wherever inside typed_gql they were created. Each operation below records
  # its own line so a test can assert the line as well as the file, and stay
  # correct when this file is edited.
  #
  # Every document here is one that does not map onto this file — a plain
  # string, an interpolated one, a sigil whose delimiter is not a string's — so
  # this is also the fixture for the fallback: the `defgql` line is all its
  # modules can be given. TypedGql.Test.DocumentLocationFixture covers the
  # `~GQL` documents that do map.
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

  # An interpolated document can splice in a value carrying newlines, so no line
  # of it is known to be a line of this file — not even one written before the
  # interpolation, since a lowercase sigil could have produced the whole string.
  @selection "id name"
  @interpolated_line __ENV__.line + 1
  defgql(:interpolated, "query Interpolated($id: ID!) { user(id: $id) { #{@selection} } }")

  # A `~GQL` sigil written with any other delimiter is neither of the two shapes
  # whose base line is known, so it falls back rather than guesses. Written
  # without spaces inside the braces because `mix credo` reads the content of a
  # parenthesised sigil as Elixir, where a space inside a brace is a `{}` with
  # one — the GraphQL it holds is the same either way.
  @parens_line __ENV__.line + 1
  defgql(:parens_sigil, ~GQL(query ParensSigil {users {id}}))

  # The document is written in TypedGql.Test.QuotedDocumentMacro, and `quote`
  # gives it this line on the way here. Anchoring to it would count the
  # document's own offsets from here and land inside `lines/0` below.
  require TypedGql.Test.QuotedDocumentMacro

  @quoted_line __ENV__.line + 1
  TypedGql.Test.QuotedDocumentMacro.define_shared_query(:shared_query)

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
      __MODULE__.Fragments.UserFields => @fragment_line,
      __MODULE__.Interpolated.Result => @interpolated_line,
      __MODULE__.Interpolated.Result.User => @interpolated_line,
      __MODULE__.ParensSigil.Result => @parens_line,
      __MODULE__.ParensSigil.Result.Users => @parens_line,
      __MODULE__.SharedQuery.Result => @quoted_line,
      __MODULE__.SharedQuery.Result.User => @quoted_line,
      __MODULE__.SharedQuery.Result.User.Profile => @quoted_line
    }
  end
end
