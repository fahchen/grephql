defmodule TypedGql.SourceAnchorTest do
  use ExUnit.Case, async: true

  alias TypedGql.Language.Field
  alias TypedGql.Language.OperationDefinition
  alias TypedGql.Language.SelectionSet
  alias TypedGql.SourceAnchor

  # The meta below is what `~GQL` really expands with. Verified by expansion on
  # Elixir 1.16 through 1.19; the project supports 1.15, where an unrecognised
  # shape has to fall back rather than produce a confidently wrong line.
  describe "base_line/1" do
    test "a heredoc's document starts on the line after the sigil" do
      assert SourceAnchor.base_line(delimiter: ~s("""), line: 22, column: 21) == 22
    end

    test "a one-line sigil's document starts on the sigil's own line" do
      assert SourceAnchor.base_line(delimiter: ~s("), line: 28, column: 21) == 27
    end

    test "any other delimiter is not mappable" do
      assert SourceAnchor.base_line(delimiter: "(", line: 28, column: 21) == nil
      assert SourceAnchor.base_line(delimiter: "'''", line: 28, column: 21) == nil
    end

    test "meta without the keys the mapping needs is not mappable" do
      assert SourceAnchor.base_line(column: 21) == nil
      assert SourceAnchor.base_line(delimiter: ~s("""), column: 21) == nil
      assert SourceAnchor.base_line(delimiter: ~s("""), line: nil, column: 21) == nil
    end

    # `quote` rewrites the line of everything it carries to the line of the
    # macro call and drops the column, while the delimiter survives. Trusting
    # the delimiter alone would anchor a document written in one file onto
    # whatever sits below the call in another.
    test "a sigil a quote moved here keeps its delimiter but is not mappable" do
      assert SourceAnchor.base_line(line: 29, delimiter: ~s(""")) == nil
      assert SourceAnchor.base_line(line: 29, delimiter: ~s(")) == nil

      assert SourceAnchor.base_line(
               line: 30,
               keep: {"lib/other.ex", 17},
               delimiter: ~s(""")
             ) == nil
    end
  end

  describe "remap/2" do
    test "rewrites every line under the node to a file line" do
      remapped = SourceAnchor.remap(operation(), 10)

      assert remapped.loc.line == 11
      assert hd(remapped.variable_definitions).loc.line == 11
      assert hd(remapped.selection_set.selections).loc.line == 12
    end

    test "keeps the rest of the location" do
      remapped = SourceAnchor.remap(operation(), 10)

      assert remapped.loc.column == 1
    end

    test "drops the lines of a document that does not map onto the file" do
      remapped = SourceAnchor.remap(operation(), nil)

      assert remapped.loc.line == nil
      assert hd(remapped.selection_set.selections).loc.line == nil
    end

    test "leaves a node that carries no line alone" do
      assert SourceAnchor.remap(%Field{name: "id"}, 10).loc == %{line: nil}
    end
  end

  describe "loc/1 and create_opts/2" do
    test "a node's location moves the caller's line and nothing else" do
      env = __ENV__
      opts = SourceAnchor.create_opts(env, SourceAnchor.loc(%Field{name: "id", loc: %{line: 7}}))

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
