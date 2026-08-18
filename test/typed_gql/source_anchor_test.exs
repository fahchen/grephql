defmodule TypedGql.SourceAnchorTest do
  use ExUnit.Case, async: true

  alias TypedGql.Language.Field
  alias TypedGql.Language.OperationDefinition
  alias TypedGql.Language.SelectionSet
  alias TypedGql.SourceAnchor

  # The meta below is what `~GQL` really expands with. Verified by expansion on
  # Elixir 1.16 through 1.19; the project supports 1.15, where an unrecognised
  # shape has to fall back rather than produce a confidently wrong line.
  describe "base/2" do
    # A heredoc's content is stripped of the same indentation on every line, so
    # its columns count from there.
    test "a heredoc's document starts on the line after the sigil" do
      assert SourceAnchor.base([delimiter: ~s("""), line: 22, column: 21], indentation: 2) ==
               %{line: 22, column: 2, file: nil}
    end

    test "a heredoc with no indentation recorded starts at the margin" do
      assert SourceAnchor.base([delimiter: ~s("""), line: 22, column: 21], []) ==
               %{line: 22, column: 0, file: nil}
    end

    # The content of `~GQL"..."` starts five characters past the `~`: the sigil
    # name and the delimiter.
    test "a one-line sigil's document starts on the sigil's own line, past the sigil" do
      assert SourceAnchor.base([delimiter: ~s("), line: 28, column: 21], []) ==
               %{line: 27, column: 25, file: nil}
    end

    test "any other delimiter is not mappable" do
      assert SourceAnchor.base([delimiter: "(", line: 28, column: 21], []) == nil
      assert SourceAnchor.base([delimiter: "'''", line: 28, column: 21], []) == nil
    end

    test "meta without the keys the mapping needs is not mappable" do
      assert SourceAnchor.base([column: 21], []) == nil
      assert SourceAnchor.base([delimiter: ~s("""), column: 21], []) == nil
      assert SourceAnchor.base([delimiter: ~s("""), line: nil, column: 21], []) == nil
    end

    # `quote` rewrites the line of everything it carries to the line of the
    # macro call and drops the column, while the delimiter survives. Trusting
    # the delimiter alone would anchor a document written in one file onto
    # whatever sits below the call in another.
    test "a sigil a quote moved here keeps its delimiter but is not mappable" do
      assert SourceAnchor.base([line: 29, delimiter: ~s(""")], []) == nil
      assert SourceAnchor.base([line: 29, delimiter: ~s(")], []) == nil
    end

    # `location: :keep` is the one form that survives being moved: it names the
    # file and line the sigil was really written at, so the document maps onto
    # the macro's own file rather than onto the file calling it.
    test "a sigil quoted with location: :keep maps onto the file it was written in" do
      assert SourceAnchor.base(
               [line: 30, keep: {"lib/other.ex", 17}, delimiter: ~s(""")],
               indentation: 6
             ) == %{line: 17, column: 6, file: "lib/other.ex"}
    end
  end

  describe "remap/2" do
    test "rewrites every line under the node to a file line" do
      remapped = SourceAnchor.remap(operation(), %{line: 10, column: 2})

      assert remapped.loc.line == 11
      assert hd(remapped.variable_definitions).loc.line == 11
      assert hd(remapped.selection_set.selections).loc.line == 12
    end

    # A column left counting from the document would name a position in neither
    # coordinate system once the line beside it counts from the file.
    test "rewrites the columns with the lines" do
      remapped = SourceAnchor.remap(operation(), %{line: 10, column: 2})

      assert remapped.loc.column == 3
      assert hd(remapped.selection_set.selections).loc.column == 5
    end

    test "drops the positions of a document that does not map onto the file" do
      remapped = SourceAnchor.remap(operation(), nil)

      assert remapped.loc.line == nil
      assert remapped.loc.column == nil
      assert hd(remapped.selection_set.selections).loc.line == nil
    end

    # A plugin may hand back a node it built itself, with a line and no column.
    # The line still maps; the column stays absent rather than being invented.
    test "maps the line of a node that carries no column" do
      remapped =
        SourceAnchor.remap(%Field{name: "id", loc: %{line: 3, column: nil}}, %{
          line: 10,
          column: 2
        })

      assert remapped.loc == %{line: 13, column: nil}
    end

    test "leaves a node that carries no line alone" do
      assert SourceAnchor.remap(%Field{name: "id"}, %{line: 10, column: 2}).loc == %{line: nil}
    end
  end

  # The file is a property of the document, not of any one node, so it is set
  # once on the env every module is built from rather than carried in each loc.
  describe "document_env/2" do
    test "a document written in another file names that file" do
      env = __ENV__
      base = %{line: 17, column: 6, file: "lib/other.ex"}

      assert SourceAnchor.document_env(env, base).file == "lib/other.ex"
    end

    test "a document written here keeps the caller's own file" do
      env = __ENV__

      assert SourceAnchor.document_env(env, %{line: 17, column: 2, file: nil}) == env
      assert SourceAnchor.document_env(env, nil) == env
    end
  end

  describe "loc/1 and create_opts/2" do
    test "a node's location moves the caller's line and nothing else" do
      env = __ENV__
      node = %Field{name: "id", loc: %{line: 7, column: 3}}
      opts = SourceAnchor.create_opts(env, SourceAnchor.loc(node))

      assert SourceAnchor.loc(node) == %{line: 7, column: 3}
      assert opts.line == 7
      assert opts.file == env.file
      assert opts.module == env.module
    end

    test "a node with no location keeps the caller's own" do
      env = __ENV__

      assert SourceAnchor.create_opts(env, SourceAnchor.loc(%Field{name: "id"})) == env
    end
  end

  defp operation do
    %OperationDefinition{
      operation: :query,
      name: "GetUser",
      variable_definitions: [
        %TypedGql.Language.VariableDefinition{
          variable: %TypedGql.Language.Variable{name: "id", loc: %{line: 1, column: 15}},
          type: %TypedGql.Language.NamedType{name: "ID"},
          loc: %{line: 1, column: 15}
        }
      ],
      selection_set: %SelectionSet{
        selections: [%Field{name: "user", loc: %{line: 2, column: 3}}],
        loc: %{line: 1, column: 25}
      },
      loc: %{line: 1, column: 1}
    }
  end
end
