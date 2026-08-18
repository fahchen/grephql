defmodule TypedGql.Test.DocumentLocationFixture do
  @moduledoc false
  # A module generated from a `~GQL` document points at the selection that
  # produced it, not at the `defgql` line. Each operation records the line its
  # sigil opens on and `lines/0` names every generated module's offset from
  # there, so the expectations stay right when this file is edited.
  #
  # `mix format` reprints a `~GQL` heredoc through TypedGql.Printer, so the
  # documents below are written the way it prints them — anything else would
  # move the lines the offsets count.
  use TypedGql,
    otp_app: :typed_gql,
    source: "schemas/integration.json",
    endpoint: "https://api.example.com/graphql"

  @get_user __ENV__.line + 1
  defgql(:get_user, ~GQL"""
  query GetUser($id: ID!) {
    user(id: $id) {
      id
      profile {
        bio
      }
    }
  }
  """)

  @search __ENV__.line + 1
  defgql(:search, ~GQL"""
  query Search($term: String!) {
    search(query: $term) {
      __typename
      ... on User {
        name
      }
    }
  }
  """)

  # Both members implement Node, so `... on Node` applies to each of them while
  # naming neither. A variant belongs at the fragment that names it, whatever
  # order the conditions were written in — matching on "applies to" instead
  # would collapse User and Post onto the Node line above them.
  @abstract_first __ENV__.line + 1
  defgql(:abstract_first, ~GQL"""
  query AbstractFirst($term: String!) {
    search(query: $term) {
      __typename
      ... on Node {
        id
      }
      ... on User {
        name
      }
      ... on Post {
        title
      }
    }
  }
  """)

  @create_post __ENV__.line + 1
  defgql(:create_post, ~GQL"""
  mutation CreatePost($input: CreatePostInput!) {
    createPost(input: $input) {
      id
    }
  }
  """)

  # A one-line sigil holds its whole document on the line it opens on, so every
  # module it generates lands there — the case the `- 1` in the base line is for.
  @one_line __ENV__.line + 1
  defgql(:one_line, ~GQL"query OneLine { users { id } }")

  @user_fields __ENV__.line + 1
  deffragment(~GQL"""
  fragment UserFields on User {
    name
    profile {
      bio
    }
  }
  """)

  @spread __ENV__.line + 1
  defgql(:user_with_fields, ~GQL"""
  query UserWithFields($id: ID!) {
    user(id: $id) {
      ...UserFields
    }
  }
  """)

  # A fragment the query defines itself is not appended by `defgql`, so its
  # nodes are already in this document's coordinates and need no offset of
  # their own — unlike one a `deffragment` registered.
  @local_fragment __ENV__.line + 1
  defgql(:local_fragment, ~GQL"""
  query LocalFragment($id: ID!) {
    user(id: $id) {
      ...Bits
    }
  }

  fragment Bits on User {
    profile {
      bio
    }
  }
  """)

  @private __ENV__.line + 1
  defgqlp(:private_query, ~GQL"""
  query PrivateQuery {
    users {
      profile {
        bio
      }
    }
  }
  """)

  # Two variables of one input type generate one module. Its location comes
  # from the first of them — but this whole `defgql` runs after :create_post,
  # which names the same type, and the later run overwrites the module.
  @shared_input __ENV__.line + 1
  defgql(:shared_input, ~GQL"""
  mutation SharedInput($first: CreatePostInput!, $second: CreatePostInput!) {
    a: createPost(input: $first) {
      id
    }
    b: createPost(input: $second) {
      id
    }
  }
  """)

  # Written in TypedGql.Test.QuotedDocumentMacro and carried here with
  # `location: :keep`, which keeps the file and line it was written at — so its
  # modules point there, not at this call. That file records the lines.
  require TypedGql.Test.QuotedDocumentMacro

  TypedGql.Test.QuotedDocumentMacro.define_kept_query(:kept_query)

  TypedGql.Test.QuotedDocumentMacro.define_kept_fragment()

  # Spreads a fragment written in another file. The modules its selections name
  # belong there; this query's own belong here.
  @cross_file __ENV__.line + 1
  defgql(:cross_file, ~GQL"""
  query CrossFile($id: ID!) {
    user(id: $id) {
      ...KeptBits
    }
  }
  """)

  @doc """
  The file line each generated module should record.

  A module's line is the line of the node that produced it: the operation for a
  `Result` or `Variables` module and for the variable definitions' input types,
  the selection for a nested module, the inline fragment for a union variant.
  """
  @spec lines() :: %{module() => pos_integer()}
  def lines do
    %{
      # `query GetUser($id: ID!) {`, then `user(id: $id) {`, then `profile {`
      __MODULE__.GetUser.Result => @get_user + 1,
      __MODULE__.GetUser.Variables => @get_user + 1,
      __MODULE__.GetUser.Result.User => @get_user + 2,
      __MODULE__.GetUser.Result.User.Profile => @get_user + 4,
      # The dispatcher belongs to the field whose type is the union, and so does
      # the Post variant: no inline fragment selects it, it decodes with the
      # shared `__typename` alone.
      __MODULE__.Search.Result => @search + 1,
      __MODULE__.Search.Result.Search.Union => @search + 2,
      __MODULE__.Search.Result.Search.Post => @search + 2,
      __MODULE__.Search.Result.Search.User => @search + 4,
      # `... on Node` at +4 applies to both members and names neither, so each
      # variant stays with the fragment that does name it.
      __MODULE__.AbstractFirst.Result.Search.Union => @abstract_first + 2,
      __MODULE__.AbstractFirst.Result.Search.User => @abstract_first + 7,
      __MODULE__.AbstractFirst.Result.Search.Post => @abstract_first + 10,
      # The input type is anchored to the variable definition that names it,
      # which the printer keeps on the signature line. `CreatePostInput` is
      # named by :shared_input below as well, and that one runs last: the module
      # it creates overwrites this one, location and all.
      __MODULE__.CreatePost.Result => @create_post + 1,
      __MODULE__.CreatePost.Variables => @create_post + 1,
      __MODULE__.CreatePost.Result.CreatePost => @create_post + 2,
      __MODULE__.OneLine.Result => @one_line,
      __MODULE__.OneLine.Result.Users => @one_line,
      __MODULE__.Fragments.UserFields => @user_fields + 1,
      __MODULE__.Fragments.UserFields.Profile => @user_fields + 3,
      # The spread's own modules come from this query, but the module named by a
      # selection *inside* the fragment belongs to the `deffragment` above.
      __MODULE__.UserWithFields.Result => @spread + 1,
      __MODULE__.UserWithFields.Result.User => @spread + 2,
      __MODULE__.UserWithFields.Result.User.Profile => @user_fields + 3,
      # A fragment the query defines itself needs no offset: `defgql` appends
      # nothing for it, so `profile {` inside it is already a line of this
      # document.
      __MODULE__.LocalFragment.Result => @local_fragment + 1,
      __MODULE__.LocalFragment.Result.User => @local_fragment + 2,
      __MODULE__.LocalFragment.Result.User.Profile => @local_fragment + 8,
      __MODULE__.PrivateQuery.Result => @private + 1,
      __MODULE__.PrivateQuery.Result.Users => @private + 2,
      __MODULE__.PrivateQuery.Result.Users.Profile => @private + 3,
      __MODULE__.SharedInput.Result => @shared_input + 1,
      __MODULE__.SharedInput.Result.A => @shared_input + 2,
      __MODULE__.SharedInput.Result.B => @shared_input + 5,
      __MODULE__.Inputs.CreatePostInput => @shared_input + 1,
      __MODULE__.CrossFile.Result => @cross_file + 1,
      __MODULE__.CrossFile.Result.User => @cross_file + 2
    }
  end
end
