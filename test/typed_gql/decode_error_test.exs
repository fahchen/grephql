defmodule TypedGql.DecodeErrorTest do
  use ExUnit.Case, async: true

  alias TypedGql.DecodeError

  describe "exception/1" do
    test "builds the struct from a message string" do
      assert %DecodeError{message: "unknown __typename \"Robot\""} =
               DecodeError.exception("unknown __typename \"Robot\"")
    end

    test "builds the struct from keyword arguments" do
      assert %DecodeError{message: "bad enum"} = DecodeError.exception(message: "bad enum")
    end

    # Asserted on the struct literal rather than on exception([]), whose
    # enforcement of @enforce_keys arrived in a later Elixir than the oldest
    # this library supports.
    test "the message field is enforced when building the struct" do
      assert_raise ArgumentError, ~r/must also be given.+\[:message\]/s, fn ->
        Code.eval_string("%TypedGql.DecodeError{}")
      end
    end
  end

  describe "message/1" do
    test "Exception.message/1 returns the stored message" do
      assert "bad enum" == Exception.message(DecodeError.exception("bad enum"))
    end
  end

  describe "exception behaviour" do
    test "the struct is an exception" do
      assert is_exception(DecodeError.exception("bad enum"))
    end

    test "raises and rescues with its message" do
      assert_raise DecodeError, "bad enum", fn -> raise DecodeError, "bad enum" end
    end

    test "carries only the message field" do
      # The struct shape is the runtime evidence for the generated t() type:
      # mix test compiles without debug_info, so typespecs are unreadable here.
      assert %DecodeError{message: "bad enum"}
             |> Map.from_struct()
             |> Map.keys()
             |> Enum.sort() == [:__exception__, :message]
    end
  end
end
