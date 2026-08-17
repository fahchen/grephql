defmodule TypedGql.JSONTest do
  # Not async: the `library/0` describe mutates :json_library, global config that
  # every other test reads through TypedGql.JSON. Sync modules run alone, after
  # all async ones have finished.
  use ExUnit.Case, async: false

  # No alias: `alias TypedGql.JSON` would shadow Elixir's built-in JSON module,
  # which is the very default `library/0` falls back to.

  describe "encode!/1 and decode/1" do
    test "round-trip a map through the configured library" do
      assert {:ok, %{"name" => "Ada", "id" => 1}} =
               TypedGql.JSON.decode(TypedGql.JSON.encode!(%{name: "Ada", id: 1}))
    end

    test "encode! renders a term as a JSON string" do
      assert TypedGql.JSON.encode!(%{"name" => "Ada"}) == ~s({"name":"Ada"})
    end

    test "decode returns an error tuple for invalid JSON" do
      assert {:error, _reason} = TypedGql.JSON.decode("not json at all")
    end
  end

  describe "normalize_error/1" do
    test "passes an exception through unchanged" do
      reason = RuntimeError.exception("boom")

      assert TypedGql.JSON.normalize_error(reason) === reason
    end

    test "wraps a non-exception term in a RuntimeError holding its inspected form" do
      reason = {:unexpected_byte, "0x6E", 0}

      assert %RuntimeError{message: message} = TypedGql.JSON.normalize_error(reason)
      assert message == inspect(reason)
    end
  end

  describe "library/0" do
    setup do
      previous = Application.get_env(:typed_gql, :json_library)

      on_exit(fn ->
        case previous do
          nil -> Application.delete_env(:typed_gql, :json_library)
          library -> Application.put_env(:typed_gql, :json_library, library)
        end
      end)
    end

    test "returns the configured module" do
      Application.put_env(:typed_gql, :json_library, Jason)

      assert TypedGql.JSON.library() == Jason
    end

    # Which module wins depends on the toolchain — the built-in JSON exists only
    # on Elixir 1.18+, and CI's floor is 1.15 — so pin the rule, not the module.
    test "falls back to the built-in JSON module, or to Jason before it existed" do
      Application.delete_env(:typed_gql, :json_library)

      expected = if Code.ensure_loaded?(JSON), do: JSON, else: Jason

      assert TypedGql.JSON.library() == expected
    end
  end
end
