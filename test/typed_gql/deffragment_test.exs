defmodule TypedGql.DeffragmentTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  describe "deffragment basic" do
    defmodule BasicClient do
      use TypedGql,
        otp_app: :typed_gql,
        source: "../support/schemas/minimal.json"

      deffragment ~GQL"""
      fragment UserFields on User {
        name
        email
      }
      """

      defgql(:get_user, ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          ...UserFields
        }
      }
      """)

      def query, do: @typed_gql_query
    end

    test "generates function with fragment spread" do
      assert function_exported?(BasicClient, :get_user, 2)
    end

    test "generates result struct with fragment fields" do
      user = struct(BasicClient.GetUser.Result.User, name: "Alice", email: "a@b.com")
      assert user.name == "Alice"
      assert user.email == "a@b.com"
    end

    test "generates fragment module under Fragments namespace" do
      assert Code.ensure_loaded?(BasicClient.Fragments.UserFields)
      frag = struct(BasicClient.Fragments.UserFields, name: "Alice", email: "a@b.com")
      assert frag.name == "Alice"
      assert frag.email == "a@b.com"
    end

    test "query document includes fragment definition" do
      assert BasicClient.query().document =~ "fragment UserFields on User"
      assert BasicClient.query().document =~ "...UserFields"
    end
  end

  describe "deffragment with plain string" do
    defmodule PlainStringClient do
      use TypedGql,
        otp_app: :typed_gql,
        source: "../support/schemas/minimal.json"

      deffragment "fragment UserName on User { name }"

      defgql(:get_user, ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          ...UserName
        }
      }
      """)
    end

    test "plain string fragment works" do
      assert function_exported?(PlainStringClient, :get_user, 2)
    end

    test "generates result with fragment fields" do
      user = struct(PlainStringClient.GetUser.Result.User, name: "Alice")
      assert user.name == "Alice"
    end
  end

  describe "deffragment with mixed fields" do
    defmodule MixedClient do
      use TypedGql,
        otp_app: :typed_gql,
        source: "../support/schemas/minimal.json"

      deffragment ~GQL"""
      fragment UserEmail on User {
        email
      }
      """

      defgql(:get_user, ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          name
          ...UserEmail
        }
      }
      """)
    end

    test "combines direct fields and fragment fields" do
      user = struct(MixedClient.GetUser.Result.User, name: "Alice", email: "a@b.com")
      assert user.name == "Alice"
      assert user.email == "a@b.com"
    end
  end

  describe "nested fragments" do
    defmodule NestedClient do
      use TypedGql,
        otp_app: :typed_gql,
        source: "../support/schemas/minimal.json"

      deffragment ~GQL"""
      fragment UserName on User {
        name
      }
      """

      deffragment ~GQL"""
      fragment UserDetails on User {
        ...UserName
        email
      }
      """

      defgql(:get_user, ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          ...UserDetails
        }
      }
      """)

      def query, do: @typed_gql_query
    end

    test "resolves nested fragment dependencies" do
      assert function_exported?(NestedClient, :get_user, 2)
    end

    test "generates all fields from nested fragments" do
      user = struct(NestedClient.GetUser.Result.User, name: "Alice", email: "a@b.com")
      assert user.name == "Alice"
      assert user.email == "a@b.com"
    end

    test "generates fragment modules for each deffragment" do
      assert Code.ensure_loaded?(NestedClient.Fragments.UserName)
      assert Code.ensure_loaded?(NestedClient.Fragments.UserDetails)
    end

    test "the outer fragment module carries the spread fragment's fields" do
      assert NestedClient.Fragments.UserDetails.__schema__(:fields) == [:name, :email]
    end

    test "query document includes both fragment definitions" do
      assert NestedClient.query().document =~ "fragment UserDetails on User"
      assert NestedClient.query().document =~ "fragment UserName on User"
    end

    test "appends nested fragment definitions in a stable order" do
      query = NestedClient.query().document

      {details_index, _len} = :binary.match(query, "fragment UserDetails on User")
      {name_index, _len} = :binary.match(query, "fragment UserName on User")

      assert details_index < name_index
    end
  end

  describe "fragment names with valid GraphQL identifiers" do
    defmodule GraphqlNameClient do
      use TypedGql,
        otp_app: :typed_gql,
        source: "../support/schemas/minimal.json"

      deffragment ~GQL"""
      fragment userFields on User {
        name
      }
      """

      deffragment ~GQL"""
      fragment _userEmail on User {
        email
      }
      """

      defgql(:get_user, ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          ...userFields
          ..._userEmail
          ... on User {
            altEmail: email
          }
        }
      }
      """)

      def query, do: @typed_gql_query
    end

    test "resolves lowercase and underscore-prefixed fragment names" do
      assert function_exported?(GraphqlNameClient, :get_user, 2)

      user =
        struct(GraphqlNameClient.GetUser.Result.User,
          name: "Alice",
          email: "a@b.com",
          alt_email: "alt@b.com"
        )

      assert user.name == "Alice"
      assert user.email == "a@b.com"
      assert user.alt_email == "alt@b.com"
    end

    test "keeps inline fragments separate from named fragment resolution" do
      query = GraphqlNameClient.query().document

      assert query =~ "fragment userFields on User"
      assert query =~ "fragment _userEmail on User"
      assert query =~ "... on User"
    end
  end

  describe "fragments defined in the query string" do
    defmodule LocalClient do
      use TypedGql,
        otp_app: :typed_gql,
        source: "../support/schemas/minimal.json"

      deffragment "fragment UserEmail on User { email }"

      # UserName is registered selecting `email`, but the query defines its own
      # UserName selecting `name` — the local definition is the one that counts.
      deffragment "fragment UserName on User { email }"

      defgql(:get_user, ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          ...UserEmail
          ...UserName
        }
      }

      fragment UserName on User {
        name
      }
      """)

      def query, do: @typed_gql_query
    end

    defmodule OnlyLocalClient do
      use TypedGql,
        otp_app: :typed_gql,
        source: "../support/schemas/minimal.json"

      # Nothing is registered: the spread resolves solely because the query
      # string defines the fragment itself.
      defgql(:get_user, ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          ...UserName
        }
      }

      fragment UserName on User {
        name
      }
      """)
    end

    test "a fragment defined next to the operation resolves with an empty registry" do
      assert OnlyLocalClient.GetUser.Result.User.__schema__(:fields) == [:name]
    end

    test "the local definition shadows the registered one of the same name" do
      assert LocalClient.GetUser.Result.User.__schema__(:fields) == [:email, :name]
    end

    test "the local definition is sent once, alongside the registered fragment" do
      document = LocalClient.query().document

      assert [_single] = :binary.matches(document, "fragment UserName on User")
      assert document =~ "fragment UserEmail on User"
    end
  end

  describe "deffragment on a union" do
    defmodule UnionClient do
      use TypedGql,
        otp_app: :typed_gql,
        source: "../support/schemas/integration.json"

      deffragment ~GQL"""
      fragment SearchFields on SearchResult {
        ... on User {
          name
        }
        ... on Post {
          title
        }
      }
      """

      def fragments, do: @typed_gql_fragments
    end

    test "the entry points at a module that exists" do
      [entry] = UnionClient.fragments()

      assert entry.result_module == UnionClient.Fragments.SearchFields.Union
      assert Code.ensure_loaded?(entry.result_module)
    end

    test "the per-member schemas carry their own selections" do
      assert UnionClient.Fragments.SearchFields.User.__schema__(:fields) == [:name]
      assert UnionClient.Fragments.SearchFields.Post.__schema__(:fields) == [:title]
    end
  end

  describe "type system definitions" do
    test "a fragment mixed with SDL is rejected at its declaration" do
      assert_raise CompileError, ~r/type system definitions cannot be sent/, fn ->
        defmodule SdlInFragment do
          use TypedGql,
            otp_app: :typed_gql,
            source: "../support/schemas/minimal.json"

          deffragment("""
          fragment UserFields on User { name }
          scalar DateTime
          """)
        end
      end
    end
  end

  describe "duplicate fragment names" do
    test "later definitions override earlier ones for subsequent queries only" do
      module_name = DuplicateRuntime

      capture_io(:stderr, fn ->
        Code.compile_string("""
        defmodule #{inspect(module_name)} do
          use TypedGql,
            otp_app: :typed_gql,
            source: "test/support/schemas/minimal.json"

          deffragment "fragment UserFields on User { name }"

          defgql :get_user_name, "query GetUserName($id: ID!) { user(id: $id) { ...UserFields } }"

          def query_name, do: @typed_gql_query

          deffragment "fragment UserFields on User { email }"

          defgql :get_user_email, "query GetUserEmail($id: ID!) { user(id: $id) { ...UserFields } }"

          def query_email, do: @typed_gql_query
        end
        """)
      end)

      # The document is reprinted from the AST, so the fragment body is indented.
      assert module_name.query_name().document =~ "fragment UserFields on User {\n  name\n}"
      refute module_name.query_name().document =~ "email"

      assert module_name.query_email().document =~ "fragment UserFields on User {\n  email\n}"
      refute module_name.query_email().document =~ "name"

      user_name =
        struct(Module.safe_concat([module_name, GetUserName, Result, User]), name: "Alice")

      assert user_name.name == "Alice"

      user_email =
        struct(Module.safe_concat([module_name, GetUserEmail, Result, User]), email: "a@b.com")

      assert user_email.email == "a@b.com"

      fragment =
        struct(Module.safe_concat([module_name, Fragments, UserFields]), email: "latest@b.com")

      assert fragment.email == "latest@b.com"
    end
  end

  describe "query without fragments" do
    defmodule NoFragmentClient do
      use TypedGql,
        otp_app: :typed_gql,
        source: "../support/schemas/minimal.json"

      deffragment ~GQL"""
      fragment UnusedFields on User {
        name
      }
      """

      defgql(:get_user, ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          name
          email
        }
      }
      """)

      def query, do: @typed_gql_query
    end

    test "does not append unused fragments" do
      refute NoFragmentClient.query().document =~ "fragment UnusedFields"
    end
  end

  describe "compile errors" do
    test "fragment with invalid type condition raises" do
      assert_raise CompileError, ~r/does not exist in the schema/, fn ->
        Code.compile_string("""
        defmodule TypedGql.Test.InvalidTypeFragment do
          use TypedGql,
            otp_app: :typed_gql,
            source: "test/support/schemas/minimal.json"

          deffragment "fragment Bad on NonExistentType { name }"
        end
        """)
      end
    end

    test "undefined fragment spread raises" do
      assert_raise CompileError, ~r/undefined fragment spread: \.\.\.NonExistent/, fn ->
        Code.compile_string("""
        defmodule TypedGql.Test.UndefinedSpread do
          use TypedGql,
            otp_app: :typed_gql,
            source: "test/support/schemas/minimal.json"

          defgql :get_user, "query($id: ID!) { user(id: $id) { ...NonExistent } }"
        end
        """)
      end
    end

    # Fragments resolve lexically, so a body may only spread what is already
    # registered — the alternative was a silently field-less fragment module.
    test "a fragment body spreading a fragment defined later raises" do
      assert_raise CompileError, ~r/undefined fragment spread: \.\.\.UserName/, fn ->
        Code.compile_string("""
        defmodule TypedGql.Test.ForwardSpread do
          use TypedGql,
            otp_app: :typed_gql,
            source: "test/support/schemas/minimal.json"

          deffragment "fragment UserDetails on User { ...UserName email }"
          deffragment "fragment UserName on User { name }"
        end
        """)
      end
    end

    test "fragment with invalid field raises" do
      assert_raise CompileError, ~r/does not exist on type/, fn ->
        Code.compile_string("""
        defmodule TypedGql.Test.InvalidFieldFragment do
          use TypedGql,
            otp_app: :typed_gql,
            source: "test/support/schemas/minimal.json"

          deffragment "fragment Bad on User { nonExistentField }"
        end
        """)
      end
    end

    test "a registered spread whose condition does not apply is a validation error" do
      assert_raise CompileError, ~r/type "Post" is not applicable to "User"/, fn ->
        Code.compile_string("""
        defmodule TypedGql.Test.RegisteredSpreadMismatch do
          use TypedGql,
            otp_app: :typed_gql,
            source: "test/support/schemas/integration.json"

          deffragment "fragment PostFields on Post { title }"
          deffragment "fragment UserStuff on User { name ...PostFields }"
        end
        """)
      end
    end

    test "a registered spread whose condition does not apply in a query is a validation error" do
      assert_raise CompileError, ~r/type "Post" is not applicable to "User"/, fn ->
        Code.compile_string("""
        defmodule TypedGql.Test.RegisteredSpreadMismatchQuery do
          use TypedGql,
            otp_app: :typed_gql,
            source: "test/support/schemas/integration.json"

          deffragment "fragment PostFields on Post { title }"

          defgql(:q, "query { user(id: \\"1\\") { name ...PostFields } }")
        end
        """)
      end
    end
  end
end
