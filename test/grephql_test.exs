defmodule GrephqlTest do
  use ExUnit.Case, async: true

  alias Grephql.Query

  describe "execute/3" do
    test "returns not_implemented stub" do
      query = %Query{
        document: "query { user { name } }",
        result_module: SomeModule,
        client_module: SomeClient
      }

      assert Grephql.execute(query) == {:error, :not_implemented}
    end

    test "accepts variables and opts" do
      query = %Query{
        document: "query($id: ID!) { user(id: $id) { name } }",
        result_module: SomeModule,
        client_module: SomeClient,
        has_variables?: true
      }

      assert Grephql.execute(query, %{id: "123"}, endpoint: "https://example.com") ==
               {:error, :not_implemented}
    end
  end
end
