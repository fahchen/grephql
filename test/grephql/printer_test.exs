defmodule Grephql.PrinterTest do
  use ExUnit.Case, async: true

  alias Grephql.Printer

  defp roundtrip(input) do
    {:ok, doc} = Grephql.Parser.parse(input)
    Printer.print(doc)
  end

  describe "operations" do
    test "named query" do
      assert roundtrip("query GetUser { user { name } }") == """
             query GetUser {
               user {
                 name
               }
             }\
             """
    end

    test "anonymous query (shorthand)" do
      assert roundtrip("{ user { name } }") == """
             {
               user {
                 name
               }
             }\
             """
    end

    test "anonymous query with operation keyword" do
      assert roundtrip("query { user { name } }") == """
             query {
               user {
                 name
               }
             }\
             """
    end

    test "mutation" do
      assert roundtrip(
               "mutation CreateUser($input: CreateUserInput!) { createUser(input: $input) { id } }"
             ) ==
               """
               mutation CreateUser($input: CreateUserInput!) {
                 createUser(input: $input) {
                   id
                 }
               }\
               """
    end
  end

  describe "variables" do
    test "single variable" do
      assert roundtrip("query GetUser($id: ID!) { user(id: $id) { name } }") == """
             query GetUser($id: ID!) {
               user(id: $id) {
                 name
               }
             }\
             """
    end

    test "multiple variables" do
      assert roundtrip(
               "query Search($q: String!, $limit: Int, $offset: Int) { search(q: $q, limit: $limit, offset: $offset) { name } }"
             ) ==
               """
               query Search($q: String!, $limit: Int, $offset: Int) {
                 search(q: $q, limit: $limit, offset: $offset) {
                   name
                 }
               }\
               """
    end

    test "variable with default value — integer" do
      assert roundtrip("query List($limit: Int = 10) { items(limit: $limit) { name } }") == """
             query List($limit: Int = 10) {
               items(limit: $limit) {
                 name
               }
             }\
             """
    end

    test "variable with default value — enum" do
      assert roundtrip("query List($status: Status = ACTIVE) { items(status: $status) { name } }") ==
               """
               query List($status: Status = ACTIVE) {
                 items(status: $status) {
                   name
                 }
               }\
               """
    end

    test "variable with default value — boolean" do
      assert roundtrip(
               "query List($includeHidden: Boolean = false) { items(includeHidden: $includeHidden) { name } }"
             ) ==
               """
               query List($includeHidden: Boolean = false) {
                 items(includeHidden: $includeHidden) {
                   name
                 }
               }\
               """
    end

    test "variable with default value — null" do
      assert roundtrip("query List($filter: String = null) { items(filter: $filter) { name } }") ==
               """
               query List($filter: String = null) {
                 items(filter: $filter) {
                   name
                 }
               }\
               """
    end

    test "variable with default value — string" do
      assert roundtrip(~s|query List($name: String = "world") { items(name: $name) { id } }|) ==
               """
               query List($name: String = "world") {
                 items(name: $name) {
                   id
                 }
               }\
               """
    end

    test "variable with list type" do
      assert roundtrip("query List($ids: [ID!]!) { items(ids: $ids) { name } }") == """
             query List($ids: [ID!]!) {
               items(ids: $ids) {
                 name
               }
             }\
             """
    end
  end

  describe "fields" do
    test "leaf field" do
      assert roundtrip("{ name }") == """
             {
               name
             }\
             """
    end

    test "multiple fields" do
      assert roundtrip("{ name email bio }") == """
             {
               name
               email
               bio
             }\
             """
    end

    test "field with alias" do
      assert roundtrip("{ account: user { name } }") == """
             {
               account: user {
                 name
               }
             }\
             """
    end

    test "field with arguments" do
      assert roundtrip("{ user(id: \"1\") { name } }") == """
             {
               user(id: "1") {
                 name
               }
             }\
             """
    end

    test "field with multiple arguments" do
      assert roundtrip("{ users(limit: 10, offset: 20) { name } }") == """
             {
               users(limit: 10, offset: 20) {
                 name
               }
             }\
             """
    end

    test "deeply nested selections" do
      assert roundtrip("{ user { posts { comments { author { name } } } } }") == """
             {
               user {
                 posts {
                   comments {
                     author {
                       name
                     }
                   }
                 }
               }
             }\
             """
    end

    test "field with alias and arguments" do
      assert roundtrip("{ firstUser: user(id: \"1\") { name } }") == """
             {
               firstUser: user(id: "1") {
                 name
               }
             }\
             """
    end
  end

  describe "inline fragments" do
    test "basic inline fragment" do
      assert roundtrip("{ search { ... on User { name } ... on Repository { fullName } } }") ==
               """
               {
                 search {
                   ... on User {
                     name
                   }
                   ... on Repository {
                     fullName
                   }
                 }
               }\
               """
    end

    test "inline fragment without type condition" do
      assert roundtrip("{ search { ... @include(if: true) { name } } }") == """
             {
               search {
                 ... @include(if: true) {
                   name
                 }
               }
             }\
             """
    end
  end

  describe "fragment spreads" do
    test "named fragment spread" do
      input = """
      query GetUser {
        user {
          ...UserFields
        }
      }

      fragment UserFields on User {
        name
        email
      }
      """

      assert roundtrip(input) == """
             query GetUser {
               user {
                 ...UserFields
               }
             }

             fragment UserFields on User {
               name
               email
             }\
             """
    end
  end

  describe "directives" do
    test "directive without arguments" do
      assert roundtrip("{ user @cached { name } }") == """
             {
               user @cached {
                 name
               }
             }\
             """
    end

    test "directive with arguments" do
      assert roundtrip("query GetUser($show: Boolean!) { user { name @skip(if: $show) } }") == """
             query GetUser($show: Boolean!) {
               user {
                 name @skip(if: $show)
               }
             }\
             """
    end

    test "multiple directives" do
      assert roundtrip("{ user @cached @deprecated { name } }") == """
             {
               user @cached @deprecated {
                 name
               }
             }\
             """
    end

    test "directive on inline fragment" do
      assert roundtrip("{ search { ... on User @skip(if: true) { name } } }") == """
             {
               search {
                 ... on User @skip(if: true) {
                   name
                 }
               }
             }\
             """
    end

    test "directive on fragment spread" do
      input = """
      {
        user {
          ...UserFields @include(if: true)
        }
      }

      fragment UserFields on User {
        name
      }
      """

      assert roundtrip(input) == """
             {
               user {
                 ...UserFields @include(if: true)
               }
             }

             fragment UserFields on User {
               name
             }\
             """
    end
  end

  describe "type references" do
    test "named type" do
      assert roundtrip("query($id: ID) { user(id: $id) { name } }") == """
             query($id: ID) {
               user(id: $id) {
                 name
               }
             }\
             """
    end

    test "non-null type" do
      assert roundtrip("query($id: ID!) { user(id: $id) { name } }") == """
             query($id: ID!) {
               user(id: $id) {
                 name
               }
             }\
             """
    end

    test "list type" do
      assert roundtrip("query($ids: [ID]) { users(ids: $ids) { name } }") == """
             query($ids: [ID]) {
               users(ids: $ids) {
                 name
               }
             }\
             """
    end

    test "non-null list of non-null" do
      assert roundtrip("query($ids: [ID!]!) { users(ids: $ids) { name } }") == """
             query($ids: [ID!]!) {
               users(ids: $ids) {
                 name
               }
             }\
             """
    end

    test "nested list type" do
      assert roundtrip("query($matrix: [[Int]]) { compute(matrix: $matrix) { result } }") == """
             query($matrix: [[Int]]) {
               compute(matrix: $matrix) {
                 result
               }
             }\
             """
    end
  end

  describe "argument values" do
    test "integer value" do
      assert roundtrip("{ users(limit: 10) { name } }") == """
             {
               users(limit: 10) {
                 name
               }
             }\
             """
    end

    test "float value" do
      assert roundtrip("{ items(price: 9.99) { name } }") == """
             {
               items(price: 9.99) {
                 name
               }
             }\
             """
    end

    test "string value" do
      assert roundtrip(~s|{ user(name: "Alice") { id } }|) == """
             {
               user(name: "Alice") {
                 id
               }
             }\
             """
    end

    test "string value with escapes" do
      assert roundtrip(~s|{ user(name: "Alice \\"Bob\\" Smith") { id } }|) == """
             {
               user(name: "Alice \\"Bob\\" Smith") {
                 id
               }
             }\
             """
    end

    test "boolean value" do
      assert roundtrip("{ users(active: true) { name } }") == """
             {
               users(active: true) {
                 name
               }
             }\
             """
    end

    test "null value" do
      assert roundtrip("{ users(filter: null) { name } }") == """
             {
               users(filter: null) {
                 name
               }
             }\
             """
    end

    test "enum value" do
      assert roundtrip("{ users(role: ADMIN) { name } }") == """
             {
               users(role: ADMIN) {
                 name
               }
             }\
             """
    end

    test "variable reference" do
      assert roundtrip("query($id: ID!) { user(id: $id) { name } }") == """
             query($id: ID!) {
               user(id: $id) {
                 name
               }
             }\
             """
    end

    test "list value" do
      assert roundtrip("{ users(ids: [1, 2, 3]) { name } }") == """
             {
               users(ids: [1, 2, 3]) {
                 name
               }
             }\
             """
    end

    test "empty list value" do
      assert roundtrip("{ users(ids: []) { name } }") == """
             {
               users(ids: []) {
                 name
               }
             }\
             """
    end

    test "nested list value" do
      assert roundtrip("{ compute(matrix: [[1, 2], [3, 4]]) { result } }") == """
             {
               compute(matrix: [[1, 2], [3, 4]]) {
                 result
               }
             }\
             """
    end

    test "object value" do
      assert roundtrip(~s|{ createUser(input: {name: "Alice", age: 30}) { id } }|) == """
             {
               createUser(input: {name: "Alice", age: 30}) {
                 id
               }
             }\
             """
    end

    test "nested object value" do
      assert roundtrip(~s|{ createUser(input: {name: "Alice", address: {city: "NYC"}}) { id } }|) ==
               """
               {
                 createUser(input: {name: "Alice", address: {city: "NYC"}}) {
                   id
                 }
               }\
               """
    end

    test "object value with enum field" do
      assert roundtrip("{ createUser(input: {role: ADMIN}) { id } }") == """
             {
               createUser(input: {role: ADMIN}) {
                 id
               }
             }\
             """
    end
  end

  describe "idempotency" do
    test "formatting already-formatted query is idempotent" do
      input = "query GetUser($id: ID!) { user(id: $id) { name email posts { title } } }"
      first = roundtrip(input)
      {:ok, doc2} = Grephql.Parser.parse(first)
      second = Printer.print(doc2)
      assert first == second
    end

    test "formatting messy whitespace produces clean output" do
      input = """
      query   GetUser(  $id :  ID!  )  {
        user(  id :  $id  )  {
          name
          email
        }
      }
      """

      assert roundtrip(input) == """
             query GetUser($id: ID!) {
               user(id: $id) {
                 name
                 email
               }
             }\
             """
    end
  end

  describe "complex queries" do
    test "query with all features combined" do
      input = """
      query SearchResults($q: String!, $limit: Int = 10, $type: SearchType = USER) {
        search(query: $q, first: $limit, type: $type) {
          ... on User {
            account: login
            name
            email @deprecated
          }
          ... on Repository {
            fullName
            stars: stargazerCount
          }
        }
      }
      """

      assert roundtrip(input) == """
             query SearchResults($q: String!, $limit: Int = 10, $type: SearchType = USER) {
               search(query: $q, first: $limit, type: $type) {
                 ... on User {
                   account: login
                   name
                   email @deprecated
                 }
                 ... on Repository {
                   fullName
                   stars: stargazerCount
                 }
               }
             }\
             """
    end

    test "multiple operations in document" do
      input = """
      query GetUser($id: ID!) { user(id: $id) { name } }
      mutation DeleteUser($id: ID!) { deleteUser(id: $id) { success } }
      """

      assert roundtrip(input) == """
             query GetUser($id: ID!) {
               user(id: $id) {
                 name
               }
             }

             mutation DeleteUser($id: ID!) {
               deleteUser(id: $id) {
                 success
               }
             }\
             """
    end
  end
end
