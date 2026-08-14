defmodule TypedGql.Test.TypespecFixture do
  @moduledoc false
  use TypedGql,
    otp_app: :typed_gql,
    source: "schemas/integration.json",
    endpoint: "https://api.example.com/graphql"

  defgql(:get_user, """
  query GetUser($id: ID!, $show: Boolean!) {
    user(id: $id) {
      id @include(if: $show)
      name
      posts {
        title
      }
    }
  }
  """)

  defgql(:list_drafts, """
  query ListDrafts {
    drafts {
      title
    }
  }
  """)

  defgql(:list_nodes, """
  query ListNodes($ids: [ID!]!) {
    nodes(ids: $ids) {
      __typename
      ... on User {
        name
      }
    }
  }
  """)
end
