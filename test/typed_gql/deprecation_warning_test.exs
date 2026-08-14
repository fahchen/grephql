defmodule TypedGql.DeprecationWarningTest do
  # Not async: :stderr is shared across all tests, so a capture here also picks
  # up whatever a concurrent test writes to it. The `refute warnings =~ ...`
  # assertion below cannot tolerate that, and `=~` (ExUnit's suggested fix for
  # async :stderr captures) does not help a negative assertion. Sync modules run
  # alone, after every async one.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "defgql deprecation warning location" do
    test "warning includes caller file path" do
      warnings =
        capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule TypedGql.Test.DeprecationWarning.DefgqlClient do
            use TypedGql,
              otp_app: :typed_gql,
              source: #{inspect(Path.expand("test/support/schemas/deprecation.json"))}

            defgql(:get_user, "query GetUser($id: ID!) { user(id: $id) { name email } }")
          end
          """)
        end)

      assert warnings =~ "field \"email\" on \"User\" is deprecated: use contactEmail instead"
      # Line 6 is where defgql is called in the compiled string
      assert warnings =~ "nofile:6"
    end

    test "warning for non-deprecated field produces no output" do
      warnings =
        capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule TypedGql.Test.DeprecationWarning.NoDeprecation do
            use TypedGql,
              otp_app: :typed_gql,
              source: #{inspect(Path.expand("test/support/schemas/deprecation.json"))}

            defgql(:get_user_safe, "query GetUserSafe($id: ID!) { user(id: $id) { name } }")
          end
          """)
        end)

      refute warnings =~ "deprecated"
    end
  end

  describe "~GQL sigil deprecation warning location" do
    test "warning includes caller file path" do
      warnings =
        capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule TypedGql.Test.DeprecationWarning.SigilClient do
            use TypedGql,
              otp_app: :typed_gql,
              source: #{inspect(Path.expand("test/support/schemas/deprecation.json"))}

            defgql :get_user_sigil, ~GQL"query GetUser($id: ID!) { user(id: $id) { name email } }"
          end
          """)
        end)

      assert warnings =~ "field \"email\" on \"User\" is deprecated: use contactEmail instead"
      # Line 6 is where defgql is called in the compiled string
      assert warnings =~ "nofile:6"
    end
  end

  describe "warning without a caller env" do
    test "is emitted without location info" do
      schema =
        TypedGql.Test.SchemaHelper.build_schema(
          types:
            Map.put(TypedGql.Test.SchemaHelper.default_types(), "User", %TypedGql.Schema.Type{
              kind: :object,
              name: "User",
              fields: %{
                "name" => %TypedGql.Schema.Field{
                  name: "name",
                  type: %TypedGql.Schema.TypeRef{kind: :scalar, name: "String"},
                  is_deprecated: true,
                  deprecation_reason: "gone"
                }
              }
            })
        )

      {:ok, doc} = TypedGql.Parser.parse(~s|query { user(id: "1") { name } }|)

      warnings =
        capture_io(:stderr, fn ->
          assert :ok = TypedGql.Validator.validate(doc, schema)
        end)

      assert warnings =~ "field \"name\" on \"User\" is deprecated: gone"
    end
  end
end
