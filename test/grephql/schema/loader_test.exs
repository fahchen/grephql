defmodule Grephql.Schema.LoaderTest do
  use ExUnit.Case, async: true

  alias Grephql.Schema
  alias Grephql.Schema.Loader

  @minimal_introspection Jason.encode!(%{
                           "data" => %{
                             "__schema" => %{
                               "queryType" => %{"name" => "Query"},
                               "mutationType" => nil,
                               "subscriptionType" => nil,
                               "types" => [
                                 %{
                                   "kind" => "OBJECT",
                                   "name" => "Query",
                                   "description" => nil,
                                   "fields" => [],
                                   "inputFields" => nil,
                                   "interfaces" => [],
                                   "enumValues" => nil,
                                   "possibleTypes" => nil
                                 }
                               ],
                               "directives" => []
                             }
                           }
                         })

  describe "load/1" do
    test "loads inline JSON string" do
      assert {:ok, %Schema{} = schema} = Loader.load(@minimal_introspection)
      assert schema.query_type == "Query"
    end

    test "loads JSON from file" do
      path = Path.join(System.tmp_dir!(), "grephql_test_schema_#{:rand.uniform(100_000)}.json")

      File.write!(path, @minimal_introspection)

      try do
        assert {:ok, %Schema{} = schema} = Loader.load(path)
        assert schema.query_type == "Query"
      after
        File.rm(path)
      end
    end

    test "returns error for nonexistent file" do
      assert {:error, "failed to read /nonexistent/path.json: no such file or directory"} =
               Loader.load("/nonexistent/path.json")
    end

    test "loads JSON with leading whitespace" do
      json = "  \n  " <> @minimal_introspection
      assert {:ok, %Schema{}} = Loader.load(json)
    end
  end
end
