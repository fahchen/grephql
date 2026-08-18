defmodule TypedGql.DocumentLocationTest do
  use ExUnit.Case, async: true

  # Elixir 1.15 does not record the sigil meta the mapping reads, so a document
  # falls back there and every module keeps the `defgql` line. That fallback is
  # asserted by TypedGql.CallerEnvTest, which runs on every version; these
  # expectations are for the mapping firing.
  @moduletag skip: not Version.match?(System.version(), ">= 1.16.0")

  alias TypedGql.Test.DocumentLocationFixture, as: Fixture
  alias TypedGql.Test.QuotedDocumentMacro

  # `__info__(:compile)[:source]` carries only the file, and every module a
  # client generates shares it. The docs chunk carries the line, which is what
  # tooling reads for "go to definition" — and, now that a `~GQL` document's
  # lines are the file's, what tells one selection from the next.
  describe "a module generated from a ~GQL document" do
    test "a result module points at its operation and a nested one at its selection" do
      assert_located(Fixture.GetUser.Result)
      assert_located(Fixture.GetUser.Result.User)
      assert_located(Fixture.GetUser.Result.User.Profile)
    end

    test "a variables module points at the operation's signature" do
      assert_located(Fixture.GetUser.Variables)
    end

    test "an input object module points at the variable definition that names it" do
      assert_located(Fixture.Inputs.CreatePostInput)
    end

    test "a union dispatcher points at the field whose type is abstract" do
      assert_located(Fixture.Search.Result.Search.Union)
    end

    test "a variant points at the inline fragment that selects it" do
      assert_located(Fixture.Search.Result.Search.User)
    end

    # No inline fragment names Post, so it has no node of its own to point at.
    test "a variant no fragment selects stays with the field" do
      assert_located(Fixture.Search.Result.Search.Post)
    end

    test "a fragment's modules point into its own deffragment" do
      assert_located(Fixture.Fragments.UserFields)
      assert_located(Fixture.Fragments.UserFields.Profile)
    end

    # The module is generated for this query, under its Result namespace, but
    # the selection that named it was written in the deffragment above — which
    # `defgql` appends to the query, so its lines are past the query's own.
    test "a module a spread produces points into the fragment it came from" do
      assert_located(Fixture.UserWithFields.Result)
      assert_located(Fixture.UserWithFields.Result.User)
      assert_located(Fixture.UserWithFields.Result.User.Profile)

      assert docs_line(Fixture.UserWithFields.Result.User.Profile) <
               docs_line(Fixture.UserWithFields.Result)
    end

    # An abstract condition applies to every member implementing it, so picking
    # the first fragment that *applies* would give User and Post the Node line
    # and make the answer depend on the order the conditions were written in.
    test "a variant points at the fragment naming it, not at an abstract one above" do
      assert_located(Fixture.AbstractFirst.Result.Search.Union)
      assert_located(Fixture.AbstractFirst.Result.Search.User)
      assert_located(Fixture.AbstractFirst.Result.Search.Post)
    end

    # `defgql` appends a *registered* fragment's source after the query, but a
    # fragment the query defines itself is already part of it — so this one
    # needs no offset, and getting that wrong would push it past the query.
    test "a fragment the query defines itself needs no offset of its own" do
      assert_located(Fixture.LocalFragment.Result)
      assert_located(Fixture.LocalFragment.Result.User)
      assert_located(Fixture.LocalFragment.Result.User.Profile)
    end

    test "a defgqlp document is located like a defgql one" do
      assert_located(Fixture.PrivateQuery.Result)
      assert_located(Fixture.PrivateQuery.Result.Users)
      assert_located(Fixture.PrivateQuery.Result.Users.Profile)
    end

    # Two fields aliased apart take one input type between them, and each gets
    # its own module from the selection that named it.
    test "aliased copies of a field are located at their own selections" do
      assert_located(Fixture.SharedInput.Result)
      assert_located(Fixture.SharedInput.Result.A)
      assert_located(Fixture.SharedInput.Result.B)
    end

    # A `~GQL"..."` sigil holds a string and a string may span lines, so the
    # column its first line starts at cannot be added to the others.
    test "a sigil whose string spans lines offsets only its first line" do
      assert_located(Fixture.Multiline.Result)
      assert_located(Fixture.Multiline.Result.User)
      assert_located(Fixture.Multiline.Result.User.Profile)
    end

    # Anchoring is by fragment name, one entry at a time, so it does not matter
    # how many spreads deep a selection is reached from.
    test "a selection reached through two spreads lands where it was written" do
      assert_located(Fixture.Fragments.InnerBits.Profile)
      assert_located(Fixture.Fragments.OuterBits)
      assert_located(Fixture.Fragments.OuterBits.Profile)
      assert_located(Fixture.NestedSpread.Result)
      assert_located(Fixture.NestedSpread.Result.User)
      assert_located(Fixture.NestedSpread.Result.User.Profile)
    end

    # The fragment is a plain string, so its own lines are unknown; the query
    # spreading it is a `~GQL` sigil, so its own are not. Each keeps what it
    # knows, and the module the spread produces — placed by a document that
    # cannot say where — falls back to the `defgql` that pulled it in.
    test "a mappable query spreading an unmappable fragment falls back per document" do
      assert_located(Fixture.SpreadsPlain.Result)
      assert_located(Fixture.Fragments.PlainBits)
      assert_located(Fixture.Fragments.PlainBits.Profile)
      assert_located(Fixture.SpreadsPlain.Result.User.Profile)
    end

    # A one-line sigil is the case the base line subtracts one for: getting it
    # wrong puts the document a line off, on the `defgql` itself.
    test "a one-line document lands on the line it was written on" do
      assert_located(Fixture.OneLine.Result)
      assert_located(Fixture.OneLine.Result.Users)
    end

    # The document was written in the macro's file and carried here by a
    # `quote location: :keep`, which keeps the file and line it came from. Every
    # other quoted form falls back — see TypedGql.CallerEnvTest.
    test "a document quoted with location: :keep points into the file it was written in" do
      for {module, line} <- QuotedDocumentMacro.kept_lines(Fixture) do
        assert docs_line(module) == line

        assert module.__info__(:compile)[:source] |> List.to_string() |> Path.basename() ==
                 "quoted_document_macro.ex"
      end
    end

    # The fragment is written in the macro's file and spread by a query in this
    # one. Its own modules belong there, and so does the module the spread
    # produces under the query's namespace — a file per node, not per document.
    test "a spread of a fragment from another file lands in that file" do
      for {module, line} <- QuotedDocumentMacro.kept_fragment_lines(Fixture) do
        assert {docs_line(module), source_file(module)} == {line, "quoted_document_macro.ex"}
      end

      spread_product = Fixture.CrossFile.Result.User.Profile

      assert {docs_line(spread_product), source_file(spread_product)} ==
               {QuotedDocumentMacro.kept_fragment_lines(Fixture)[
                  Module.safe_concat([Fixture, Fragments, KeptBits, Profile])
                ], "quoted_document_macro.ex"}
    end

    test "the query's own modules stay in the file the query was written in" do
      assert_located(Fixture.CrossFile.Result)
      assert_located(Fixture.CrossFile.Result.User)
    end
  end

  # A generated module records a line and no column, because that is all
  # `Module.create/3` takes. The column is for whoever reads the node, which is
  # a generation plugin — so the only way to prove that half is to be one, and
  # to check the position against the text actually sitting there.
  describe "the position a plugin is handed" do
    test "names the text it was written at, in a heredoc" do
      assert_reads(Fixture.GetUser.Result, %{
        user: "user(id: $id) {",
        id: "id",
        profile: "profile {",
        bio: "bio"
      })
    end

    # Every line but the first begins at the margin, so a base column added to
    # all of them would push these past their text.
    test "names the text it was written at, in a sigil whose string spans lines" do
      assert_reads(Fixture.Multiline.Result, %{
        user: "user(id: $id) {",
        profile: "profile {",
        bio: "bio"
      })
    end
  end

  describe "reading the generated modules rather than the fixture" do
    # Read off the generated modules, not off the fixture's own map: comparing
    # two entries of `lines/0` compares two literals and would pass however the
    # mapping behaved.
    test "modules from one operation are told apart by the selection they came from" do
      assert docs_line(Fixture.GetUser.Result) < docs_line(Fixture.GetUser.Result.User)

      assert docs_line(Fixture.GetUser.Result.User) <
               docs_line(Fixture.GetUser.Result.User.Profile)

      assert docs_line(Fixture.Search.Result.Search.Union) <
               docs_line(Fixture.Search.Result.Search.User)
    end
  end

  defp assert_located(module) do
    assert docs_line(module) == Map.fetch!(Fixture.lines(), module)
    assert source_file(module) == "document_location_fixture.ex"
  end

  # Slices the fixture at the position the plugin was handed and asserts the
  # text found there, so a column that drifts has nowhere to hide.
  defp assert_reads(module, expected) do
    lines = String.split(File.read!("test/support/document_location_fixture.ex"), "\n")
    located = Map.fetch!(Fixture.captured_locations(), module)

    for {field, text} <- expected do
      loc = Map.fetch!(located, field)
      found = lines |> Enum.at(loc.line - 1) |> String.slice(loc.column - 1, String.length(text))

      assert found == text, "#{field} at #{loc.line}:#{loc.column} reads #{inspect(found)}"
    end
  end

  defp source_file(module) do
    module.__info__(:compile)[:source] |> List.to_string() |> Path.basename()
  end

  defp docs_line(module) do
    {:docs_v1, line, _lang, _format, _doc, _meta, _docs} = Code.fetch_docs(module)
    line
  end
end
