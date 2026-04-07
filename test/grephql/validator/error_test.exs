defmodule Grephql.Validator.ErrorTest do
  use ExUnit.Case, async: true

  alias Grephql.Validator.Error

  describe "format/2" do
    test "includes line and column when both present" do
      error = %Error{message: "field is deprecated", line: 3, column: 15}
      assert Error.format(error) == "(3:15) field is deprecated"
    end

    test "includes only line when column is nil" do
      error = %Error{message: "field is deprecated", line: 3}
      assert Error.format(error) == "(3) field is deprecated"
    end

    test "returns bare message when both nil" do
      error = %Error{message: "field is deprecated"}
      assert Error.format(error) == "field is deprecated"
    end

    test "applies line offset when provided" do
      error = %Error{message: "field is deprecated", line: 2, column: 5}
      assert Error.format(error, 10) == "(12:5) field is deprecated"
    end

    test "applies line offset with line only" do
      error = %Error{message: "field is deprecated", line: 1}
      assert Error.format(error, 20) == "(21) field is deprecated"
    end

    test "ignores line offset when no location" do
      error = %Error{message: "field is deprecated"}
      assert Error.format(error, 10) == "field is deprecated"
    end
  end
end
