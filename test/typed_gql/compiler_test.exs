defmodule TypedGql.CompilerTest do
  use ExUnit.Case, async: true

  alias TypedGql.Compiler
  alias TypedGql.Language.Fragment
  alias TypedGql.Query
  alias TypedGql.Test.SchemaHelper

  describe "compile!/3" do
    test "returns a %Query{} carrying the printed document" do
      query =
        compile!(TypedGql.Test.CompilerDoc, :get_user, """
        query   GetUser   { user(id: "1") { name email } }
        """)

      assert %Query{} = query

      assert query.document == """
             query GetUser {
               user(id: "1") {
                 name
                 email
               }
             }\
             """
    end

    test "reports the operation type and name" do
      query =
        compile!(TypedGql.Test.CompilerNamed, :get_user, ~s|query GetUser { users { name } }|)

      assert query.operation_type == "query"
      assert query.operation_name == "GetUser"
    end

    test "carries the client module and function name it was given" do
      query = compile!(TypedGql.Test.CompilerOpts, :fetch_users, ~s|query { users { name } }|)

      assert query.client_module == TypedGql.Test.CompilerOpts
      assert query.function_name == :fetch_users
    end

    test "populates the generated result modules, decode root first" do
      query =
        compile!(TypedGql.Test.CompilerResult, :get_user, ~s|query { user(id: "1") { name } }|)

      assert query.result_module == TypedGql.Test.CompilerResult.GetUser.Result

      assert query.result_modules == [
               TypedGql.Test.CompilerResult.GetUser.Result,
               TypedGql.Test.CompilerResult.GetUser.Result.User
             ]

      assert Code.ensure_loaded?(query.result_module)
    end

    test "generates a variables module and variable docs for an operation with variables" do
      query =
        compile!(
          TypedGql.Test.CompilerVars,
          :get_user,
          ~s|query GetUser($id: ID!) { user(id: $id) { name } }|
        )

      assert query.has_variables?
      assert query.variables_module == TypedGql.Test.CompilerVars.GetUser.Variables
      assert query.variable_docs == [%{name: "id", type: "ID!", required: true}]
    end

    test "an operation without variables gets no variables module" do
      query = compile!(TypedGql.Test.CompilerNoVars, :get_user, ~s|query { users { name } }|)

      refute query.has_variables?
      assert query.variables_module == nil
      assert query.variable_docs == []
    end

    test "an anonymous operation compiles with a nil operation name" do
      query =
        compile!(TypedGql.Test.CompilerAnon, :get_user, ~s|query { user(id: "1") { name } }|)

      assert query.operation_name == nil
      assert query.operation_type == "query"
      # The module name comes from the function name, not the operation name.
      assert query.result_module == TypedGql.Test.CompilerAnon.GetUser.Result
    end

    test "a fragment defined next to the operation is kept in the transmitted document" do
      query =
        compile!(TypedGql.Test.CompilerInlineFrag, :get_user, """
        query GetUser { user(id: "1") { ...UserFields } }
        fragment UserFields on User { name }
        """)

      assert query.document =~ "...UserFields"
      assert query.document =~ "fragment UserFields on User {"
    end

    test "raises CompileError for a document with no operation" do
      assert_raise CompileError, ~r/no operation definition found in query/, fn ->
        compile!(TypedGql.Test.CompilerNoOp, :get_user, "fragment F on User { name }")
      end
    end

    test "raises CompileError for a document with multiple operations" do
      message =
        ~r/multiple operation definitions found; defgql supports exactly one operation per query/

      assert_raise CompileError, message, fn ->
        compile!(TypedGql.Test.CompilerMultiOp, :get_user, """
        query A { users { name } }
        query B { users { email } }
        """)
      end
    end

    test "raises CompileError on a parse error" do
      assert_raise CompileError, ~r/GraphQL parse error/, fn ->
        compile!(TypedGql.Test.CompilerParseError, :get_user, ~s|query { users { name }|)
      end
    end

    test "raises CompileError listing validation errors" do
      assert_raise CompileError, ~r/GraphQL validation errors/, fn ->
        compile!(TypedGql.Test.CompilerInvalid, :get_user, ~s|query { users { ghost } }|)
      end
    end
  end

  describe "compile_document!/4" do
    test "compiles an already parsed document" do
      {:ok, document} = TypedGql.Parser.parse(~s|query GetUser { user(id: "1") { name } }|)

      query =
        Compiler.compile_document!(document, "", SchemaHelper.build_schema(),
          client_module: TypedGql.Test.CompilerDocument,
          function_name: :get_user,
          caller_env: __ENV__
        )

      assert query.operation_name == "GetUser"
      assert query.result_module == TypedGql.Test.CompilerDocument.GetUser.Result
    end

    test "prints the document it is given and ignores the query string argument" do
      {:ok, document} = TypedGql.Parser.parse(~s|query GetUser { users { name } }|)

      query =
        Compiler.compile_document!(
          document,
          "not the query that is sent",
          SchemaHelper.build_schema(),
          client_module: TypedGql.Test.CompilerIgnoredString,
          function_name: :get_user,
          caller_env: __ENV__
        )

      assert query.document == "query GetUser {\n  users {\n    name\n  }\n}"
    end
  end

  describe "compile_fragment!/3" do
    test "returns the source, the parsed fragment and the generated result module" do
      entry =
        compile_fragment!(TypedGql.Test.CompilerFragment, "fragment UserFields on User { name }")

      assert %{source: source, fragment: %Fragment{} = fragment, result_module: result_module} =
               entry

      assert source == "fragment UserFields on User { name }"
      assert fragment.name == "UserFields"
      assert fragment.type_condition.name == "User"
      assert result_module == TypedGql.Test.CompilerFragment.Fragments.UserFields
    end

    test "the entry carries no key beyond source, fragment, result_module and base" do
      entry = compile_fragment!(TypedGql.Test.CompilerFragKeys, "fragment F on User { name }")

      assert Enum.sort(Map.keys(entry)) == [:base, :fragment, :result_module, :source]
    end

    # The entry is what a later `defgql` spreading this fragment reads to place
    # the modules it generates, so the base has to survive the round trip.
    test "the entry records the base it was compiled with" do
      base = %{line: 12, column: 2, continuation_column: 2, file: nil}

      entry =
        compile_fragment!(TypedGql.Test.CompilerFragBase, "fragment F on User { name }",
          document_base: base
        )

      assert entry.base == base
    end

    test "the entry records no base for a document that was given none" do
      entry = compile_fragment!(TypedGql.Test.CompilerFragNoBase, "fragment F on User { name }")

      assert entry.base == nil
    end

    test "the recorded source is trimmed" do
      entry =
        compile_fragment!(TypedGql.Test.CompilerFragTrim, "\n  fragment F on User { name }\n")

      assert entry.source == "fragment F on User { name }"
    end

    test "the generated result module is compiled and loadable" do
      entry = compile_fragment!(TypedGql.Test.CompilerFragModule, "fragment F on User { name }")

      assert Code.ensure_loaded?(entry.result_module)
    end

    test "raises CompileError when the string defines no fragment" do
      assert_raise CompileError, ~r/no fragment definition found/, fn ->
        compile_fragment!(TypedGql.Test.CompilerFragNone, ~s|query { users { name } }|)
      end
    end

    test "raises CompileError when the string defines more than one fragment" do
      message =
        ~r/multiple fragment definitions found; deffragment supports exactly one fragment per call/

      assert_raise CompileError, message, fn ->
        compile_fragment!(TypedGql.Test.CompilerFragMulti, """
        fragment A on User { name }
        fragment B on User { email }
        """)
      end
    end

    test "raises CompileError listing fragment validation errors" do
      assert_raise CompileError, ~r/GraphQL fragment validation errors/, fn ->
        compile_fragment!(TypedGql.Test.CompilerFragInvalid, "fragment F on User { ghost }")
      end
    end
  end

  # Each test needs its own client module: the generated modules are defined at
  # test runtime, so a shared name would be redefined across tests.
  defp compile!(client_module, function_name, query_string) do
    Compiler.compile!(query_string, SchemaHelper.build_schema(),
      client_module: client_module,
      function_name: function_name,
      caller_env: __ENV__
    )
  end

  defp compile_fragment!(client_module, fragment_string, opts \\ []) do
    Compiler.compile_fragment!(
      fragment_string,
      SchemaHelper.build_schema(),
      [client_module: client_module, caller_env: __ENV__] ++ opts
    )
  end
end
