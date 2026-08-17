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

    # Reading the docs chunk rather than the fixture's own map is what makes
    # this a claim about the change: comparing two entries of `lines/0` would
    # compare two literals and pass under any mutation of the mapping.
    test "operations in one client are told apart by line, not just by file" do
      recorded =
        Enum.map(
          [
            Fixture.GetUser.Result,
            Fixture.Search.Result.Search.Union,
            Fixture.Inputs.CreatePostInput,
            Fixture.Fragments.UserFields
          ],
          &docs_line/1
        )

      assert recorded == Enum.uniq(recorded)
    end
  end

  # A document whose lines are not this file's gets no mapping at all: every
  # module it generates keeps the caller's own location, which is what a `~GQL`
  # heredoc used to give too. TypedGql.DocumentLocationTest covers the documents
  # that do map, and TypedGql.SourceAnchorTest the shape check that decides.
  describe "a document that does not map onto the file" do
    test "an interpolated document keeps the defgql line" do
      assert_located(Fixture.Interpolated.Result)
      assert_located(Fixture.Interpolated.Result.User)
    end

    test "a ~GQL sigil with an unrecognised delimiter keeps the defgql line" do
      assert_located(Fixture.ParensSigil.Result)
      assert_located(Fixture.ParensSigil.Result.Users)
    end

    # The document is a heredoc, so its delimiter says "mappable" — but `quote`
    # gave it the line of the call rather than of the text. Counting the
    # document's own offsets from there would put these modules on the lines
    # below the call, which are `lines/0` and this file's other operations.
    test "a document a quote carried here keeps the defgql line" do
      assert_located(Fixture.SharedQuery.Result)
      assert_located(Fixture.SharedQuery.Result.User)
      assert_located(Fixture.SharedQuery.Result.User.Profile)
    end
  end

  # The fixture records the line each operation was declared on, so this stays
  # correct when that file is edited. The two facts come from different places:
  # the docs chunk gained a :source_path only in Elixir 1.18, while the compile
  # info has carried the file all along and has never carried the line.
  defp assert_located(module) do
    file = List.to_string(module.__info__(:compile)[:source])

    assert docs_line(module) == Map.fetch!(Fixture.lines(), module)
    assert Path.basename(file) == "caller_location_fixture.ex"
  end

  defp docs_line(module) do
    {:docs_v1, line, _lang, _format, _doc, _meta, _docs} = Code.fetch_docs(module)
    line
  end
end
