defmodule TypedGql.CallerEnvTest do
  use ExUnit.Case, async: true

  alias TypedGql.Test.CallerLocationFixture, as: Fixture

  # `__info__(:compile)[:source]` carries only the file, and every module in a
  # client shares that. The docs chunk carries the line too, which is what
  # distinguishes one `defgql` from the next — and it is what tooling reads for
  # "go to definition".
  describe "generated module source location" do
    test "a result module and its nested modules point at their own defgql" do
      assert_located(Fixture.GetUser.Result)
      assert_located(Fixture.GetUser.Result.User)
    end

    test "a variables module points at its own defgql" do
      assert_located(Fixture.GetUser.Variables)
    end

    # The dispatcher used to be created by Types.Union.define/2, which passed
    # the __ENV__ of union.ex, so every union in every client pointed there.
    test "a union dispatcher points at its own defgql" do
      assert_located(Fixture.Search.Result.Search.Union)
      assert_located(Fixture.Search.Result.Search.User)
    end

    test "an input object module points at its own defgql" do
      assert_located(Fixture.Inputs.CreatePostInput)
    end

    test "a fragment module points at its own deffragment" do
      assert_located(Fixture.Fragments.UserFields)
    end

    test "operations in one client are told apart by line, not just by file" do
      lines = Fixture.lines()

      assert lines[Fixture.GetUser.Result] != lines[Fixture.Search.Result.Search.Union]

      assert length(Enum.uniq(Map.values(lines))) == 4
    end
  end

  # The fixture records the line each operation was declared on, so this stays
  # correct when that file is edited.
  defp assert_located(module) do
    expected_line = Map.fetch!(Fixture.lines(), module)
    {:docs_v1, line, _lang, _format, _doc, meta, _docs} = Code.fetch_docs(module)

    assert line == expected_line
    assert Path.basename(List.to_string(meta[:source_path])) == "caller_location_fixture.ex"
  end
end
