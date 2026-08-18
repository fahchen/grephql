defmodule TypedGql.DocumentLocationTest do
  use ExUnit.Case, async: true

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
    file = List.to_string(module.__info__(:compile)[:source])

    assert docs_line(module) == Map.fetch!(Fixture.lines(), module)
    assert Path.basename(file) == "document_location_fixture.ex"
  end

  defp docs_line(module) do
    {:docs_v1, line, _lang, _format, _doc, _meta, _docs} = Code.fetch_docs(module)
    line
  end
end
