defmodule Grephql.DeprecationWarningTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  describe "defgql deprecation warning location" do
    test "warning includes caller file path" do
      warnings =
        capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule Grephql.Test.DeprecationWarning.DefgqlClient do
            use Grephql,
              otp_app: :grephql,
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
          defmodule Grephql.Test.DeprecationWarning.NoDeprecation do
            use Grephql,
              otp_app: :grephql,
              source: #{inspect(Path.expand("test/support/schemas/deprecation.json"))}

            defgql(:get_user_safe, "query GetUserSafe($id: ID!) { user(id: $id) { name } }")
          end
          """)
        end)

      assert warnings == ""
    end
  end

  describe "~GQL sigil deprecation warning location" do
    test "warning includes caller file path" do
      warnings =
        capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule Grephql.Test.DeprecationWarning.SigilClient do
            use Grephql,
              otp_app: :grephql,
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
end
