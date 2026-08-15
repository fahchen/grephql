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

    test "requires the enforced message field" do
      assert_raise ArgumentError, fn -> DecodeError.exception([]) end
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
