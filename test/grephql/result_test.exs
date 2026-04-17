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

    test "defaults assigns to empty map" do
      result = %Result{}

      assert result.assigns == %{}
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

  describe "put_resp_assign/3" do
    test "stores a key-value pair in response private" do
      resp = %Req.Response{status: 200, body: ""}
      resp = Result.put_resp_assign(resp, :extensions, %{"cost" => 10})

      assert resp.private.grephql == %{extensions: %{"cost" => 10}}
    end

    test "preserves existing assigns" do
      resp =
        %Req.Response{status: 200, body: ""}
        |> Result.put_resp_assign(:foo, 1)
        |> Result.put_resp_assign(:bar, 2)

      assert resp.private.grephql == %{foo: 1, bar: 2}
    end
  end

  describe "assigns_from_response/1" do
    test "extracts assigns from response private" do
      resp =
        Result.put_resp_assign(%Req.Response{status: 200, body: ""}, :extensions, %{"cost" => 10})

      assert Result.assigns_from_response(resp) == %{extensions: %{"cost" => 10}}
    end

    test "returns empty map when no grephql key in private" do
      resp = %Req.Response{status: 200, body: ""}

      assert Result.assigns_from_response(resp) == %{}
    end
  end
end
