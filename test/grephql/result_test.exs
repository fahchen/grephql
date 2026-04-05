defmodule Grephql.ResultTest do
  use ExUnit.Case, async: true

  alias Grephql.Error
  alias Grephql.Result

  describe "struct" do
    test "creates with data and errors" do
      error = %Error{message: "partial"}
      result = %Result{data: %{name: "Alice"}, errors: [error]}

      assert result.data == %{name: "Alice"}
      assert [%Error{message: "partial"}] = result.errors
    end

    test "defaults errors to empty list" do
      result = %Result{data: %{name: "Alice"}}

      assert result.errors == []
    end

    test "data defaults to nil" do
      result = %Result{}

      assert result.data == nil
      assert result.errors == []
    end

    test "data can be nil with errors" do
      result = %Result{data: nil, errors: [%Error{message: "fail"}]}

      assert result.data == nil
      assert length(result.errors) == 1
    end
  end
end
