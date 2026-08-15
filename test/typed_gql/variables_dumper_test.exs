defmodule TypedGql.VariablesDumperTest do
  use ExUnit.Case, async: true

  alias TypedGql.Test.Variables.Input
  alias TypedGql.Test.Variables.Metadata
  alias TypedGql.Test.Variables.Params
  alias TypedGql.Test.Variables.Tag
  alias TypedGql.VariablesDumper

  describe "dump/2" do
    test "a field the caller provided is dumped" do
      assert VariablesDumper.dump(%Params{id: "u1"}, %{id: "u1"}) == %{id: "u1"}
    end

    test "a field the caller omitted is left out entirely" do
      dumped = VariablesDumper.dump(%Params{id: "u1"}, %{id: "u1"})

      refute Map.has_key?(dumped, :showEmail)
    end

    test "a field the caller passed as nil is dumped as nil" do
      dumped =
        VariablesDumper.dump(%Params{id: "u1", show_email: nil}, %{id: "u1", show_email: nil})

      assert dumped == %{id: "u1", showEmail: nil}
    end

    test "a field is dumped under its schema source, not its struct name" do
      dumped = VariablesDumper.dump(%Params{show_email: true}, %{show_email: true})

      assert dumped == %{showEmail: true}
    end

    test "a param key matching no schema field is ignored" do
      dumped = VariablesDumper.dump(%Params{id: "u1"}, %{id: "u1", nonsense: "x"})

      assert dumped == %{id: "u1"}
    end

    test "string-keyed params prune the same fields as atom-keyed ones" do
      variables = %Params{id: "u1"}

      assert VariablesDumper.dump(variables, %{"id" => "u1"}) ==
               VariablesDumper.dump(variables, %{id: "u1"})
    end

    test "an outer string key and an inner atom key both resolve" do
      variables = %Params{
        id: "u1",
        input: %Input{title: "T", metadata: %Metadata{seo_title: "S"}}
      }

      dumped =
        VariablesDumper.dump(variables, %{
          "id" => "u1",
          "input" => %{title: "T", metadata: %{seo_title: "S"}}
        })

      assert dumped == %{id: "u1", input: %{title: "T", metadata: %{seoTitle: "S"}}}
    end

    test "an outer atom key and an inner string key both resolve" do
      variables = %Params{id: "u1", input: %Input{title: "T", tags: [%Tag{name: "a"}]}}

      dumped =
        VariablesDumper.dump(variables, %{
          id: "u1",
          input: %{"title" => "T", "tags" => [%{"name" => "a"}]}
        })

      assert dumped == %{id: "u1", input: %{title: "T", tags: [%{name: "a"}]}}
    end

    test "params given as an empty map prune every field" do
      assert VariablesDumper.dump(%Params{id: "u1", show_email: true}, %{}) == %{}
    end
  end

  describe "dump/2 with a nested embed" do
    test "an embedded schema is pruned against its own params" do
      variables = %Params{input: %Input{title: "T"}}

      dumped = VariablesDumper.dump(variables, %{input: %{title: "T"}})

      assert dumped == %{input: %{title: "T"}}
    end

    test "pruning recurses through every embed level" do
      variables = %Params{input: %Input{title: "T", metadata: %Metadata{seo_title: "S"}}}

      dumped =
        VariablesDumper.dump(variables, %{input: %{title: "T", metadata: %{seo_title: "S"}}})

      assert dumped == %{input: %{title: "T", metadata: %{seoTitle: "S"}}}
    end

    test "an embed the caller passed as nil is dumped as nil rather than descended into" do
      dumped = VariablesDumper.dump(%Params{input: nil}, %{input: nil})

      assert dumped == %{input: nil}
    end

    test "an embed the caller omitted is left out even when the struct carries one" do
      variables = %Params{id: "u1", input: %Input{title: "T"}}

      dumped = VariablesDumper.dump(variables, %{id: "u1"})

      assert dumped == %{id: "u1"}
    end
  end

  describe "dump/2 with a list of embeds" do
    test "each element is pruned against the params at its own position" do
      variables = %Params{
        input: %Input{tags: [%Tag{name: "a"}, %Tag{name: "b", color_hex: "fff"}]}
      }

      dumped =
        VariablesDumper.dump(variables, %{
          input: %{tags: [%{name: "a"}, %{name: "b", color_hex: "fff"}]}
        })

      assert dumped == %{input: %{tags: [%{name: "a"}, %{name: "b", colorHex: "fff"}]}}
    end

    test "an empty list dumps as an empty list" do
      dumped = VariablesDumper.dump(%Params{input: %Input{tags: []}}, %{input: %{tags: []}})

      assert dumped == %{input: %{tags: []}}
    end
  end
end
