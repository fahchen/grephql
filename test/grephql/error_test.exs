defmodule Grephql.ErrorTest do
  use ExUnit.Case, async: true

  alias Grephql.Error

  describe "from_json/1" do
    test "parses complete error" do
      json = %{
        "message" => "Not found",
        "locations" => [%{"line" => 2, "column" => 3}],
        "path" => ["user", "friends", 0, "name"],
        "extensions" => %{"code" => "NOT_FOUND"}
      }

      error = Error.from_json(json)

      assert error.message == "Not found"
      assert error.locations == [%{"line" => 2, "column" => 3}]
      assert error.path == ["user", "friends", 0, "name"]
      assert error.extensions == %{"code" => "NOT_FOUND"}
    end

    test "defaults optional fields" do
      json = %{"message" => "Something went wrong"}

      error = Error.from_json(json)

      assert error.message == "Something went wrong"
      assert error.locations == nil
      assert error.path == nil
      assert error.extensions == nil
    end

    test "parses multiple locations" do
      json = %{
        "message" => "Syntax error",
        "locations" => [
          %{"line" => 1, "column" => 5},
          %{"line" => 3, "column" => 10}
        ]
      }

      error = Error.from_json(json)

      assert length(error.locations) == 2
    end

    test "path with mixed string and integer segments" do
      json = %{
        "message" => "Error",
        "path" => ["users", 2, "address", "city"]
      }

      error = Error.from_json(json)

      assert error.path == ["users", 2, "address", "city"]
    end

    test "empty path and locations" do
      json = %{
        "message" => "Error",
        "path" => [],
        "locations" => []
      }

      error = Error.from_json(json)

      assert error.path == []
      assert error.locations == []
    end
  end
end
