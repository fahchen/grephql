defmodule TypedGql.SourceAnchor do
  @moduledoc false
  # Maps a position inside a compiled GraphQL document onto the position in the
  # Elixir file that wrote it, so a generated module points at the selection
  # that produced it rather than at the whole `defgql`.
  #
  # Requires Elixir 1.16 or later: 1.15 does not record the sigil meta the
  # arithmetic reads, so every document falls back there and each module keeps
  # the `defgql` line, which is what all of them had before this existed.
  #
  # A `~GQL` sigil is the only document form whose lines are known to be the
  # file's: the sigil's AST meta says where it opens, and its delimiter says
  # whether the document starts on the next line (`~GQL"""`) or on that very
  # one (`~GQL"..."`). Any other form — a plain string, an interpolated one —
  # can carry newlines that were never written in this file, so it has no base
  # and every node position is dropped rather than guessed: a wrong location
  # sends the reader to unrelated code, which is worse than the coarse `defgql`
  # line a dropped one falls back to.

  @typedoc """
  Where the document sits in the file, or nil when it does not map onto one.

  `:column` is what document line 1 starts at and `:continuation_column` what
  every line after it does — the same for a heredoc, which is indented alike
  throughout, but not for a sigil whose first line starts past `~GQL"`. `:file`
  is set only when the document was not written in the caller's own file: a
  macro that emitted the `defgql` with `quote location: :keep`.
  """
  @type base() ::
          %{
            line: non_neg_integer(),
            column: non_neg_integer(),
            continuation_column: non_neg_integer(),
            file: binary() | nil
          }
          | nil

  @typedoc "A location in the source file, once `remap/2` has rewritten it."
  @type loc() :: %{line: pos_integer(), column: pos_integer(), file: binary() | nil}

  @heredoc_delimiter ~s(""")
  @string_delimiter ~s(")

  # A one-line sigil's content begins five characters past the column the sigil
  # opens on — `~GQL` and its delimiter — and four of those are the base, since
  # the content's own column starts at 1 rather than 0.
  @sigil_offset String.length("~GQL")

  @doc """
  Where a `~GQL` sigil's document starts in the file, from the sigil's AST meta.

  `:line` and `:column` are where the sigil opens. A heredoc's content starts on
  the next line, indented by `binary_meta`'s `:indentation` on every line; a
  one-line sigil's starts on that same line, just past the sigil itself. Any
  other delimiter, and any meta missing the keys the arithmetic needs, is
  unmappable rather than guessed at.
  """
  @spec base(keyword(), keyword()) :: base()
  def base(sigil_meta, binary_meta) do
    case origin(sigil_meta) do
      {:ok, origin} -> document_start(sigil_meta[:delimiter], origin, binary_meta)
      :error -> nil
    end
  end

  # Where the sigil itself sits, and in which file, or :error when the meta does
  # not say. A sigil written inside a `quote` reaches the macro linified to the
  # line of the macro *call* while keeping its delimiter, so the delimiter alone
  # would let a document from another file anchor onto whatever happens to sit
  # below the call. The tokenizer records a `:column` only for a sigil it read at
  # this position and drops it when `quote` rewrites the line, so its presence is
  # what says the line and the text belong together. `quote location: :keep`
  # keeps them together too, in `:keep`, which names the file as well.
  defp origin(sigil_meta) do
    case {sigil_meta[:keep], sigil_meta[:column], sigil_meta[:line]} do
      {{file, line}, _column, _line} when is_binary(file) and is_integer(line) ->
        {:ok, %{line: line, column: nil, file: file}}

      {nil, column, line} when is_integer(column) and is_integer(line) ->
        {:ok, %{line: line, column: column, file: nil}}

      _other ->
        :error
    end
  end

  # A heredoc's content starts on the line after the sigil, stripped of the same
  # indentation on every line, so one base column serves all of them. A one-line
  # sigil's starts on that same line, past the sigil — and needs a column to
  # count from, which a `:keep` origin does not have. Any other delimiter is
  # neither shape, so it is refused rather than guessed at.
  defp document_start(@heredoc_delimiter, origin, binary_meta) do
    # Elixir records `:indentation` for every heredoc, `0` included when the
    # content sits at the margin, so the fallback below stands for a heredoc
    # whose meta a future version stopped writing — and `0` is what an
    # unindented one would have said anyway.
    indentation = binary_meta[:indentation] || 0

    %{
      line: origin.line,
      column: indentation,
      continuation_column: indentation,
      file: origin.file
    }
  end

  defp document_start(@string_delimiter, %{column: column} = origin, _binary_meta)
       when is_integer(column) do
    %{
      line: origin.line - 1,
      column: column + @sigil_offset,
      continuation_column: 0,
      file: origin.file
    }
  end

  defp document_start(_delimiter, _origin, _binary_meta), do: nil

  @doc """
  Rewrites every `loc` under `node` from a document position to a file one.

  A nil `base` means the document does not map onto the file, so the positions
  are dropped instead: a node whose line is nil resolves to the caller's own
  location in `create_opts/2`. The column moves with the line, so the two never
  name different coordinate systems — a file line beside a document column
  would read as a position that is nowhere.
  """
  @spec remap(struct(), base()) :: struct()
  def remap(%_struct{} = node, base) do
    node
    |> Map.from_struct()
    |> Enum.reduce(node, fn {key, value}, acc ->
      Map.put(acc, key, remap_value(value, base))
    end)
    |> remap_loc(base)
  end

  defp remap_value(%_struct{} = node, base), do: remap(node, base)

  defp remap_value(values, base) when is_list(values),
    do: Enum.map(values, &remap_value(&1, base))

  defp remap_value(other, _base), do: other

  # Only a node that carries a line is rewritten: `TypedGql.Language.Argument`
  # defaults its `loc` to a tuple, and every other node defaults the line to nil.
  defp remap_loc(%{loc: %{line: line} = loc} = node, base) when is_integer(line) do
    remapped =
      loc
      |> Map.put(:line, file_line(line, base))
      |> Map.put(:column, file_column(loc, base))
      |> Map.put(:file, base && base.file)

    %{node | loc: remapped}
  end

  defp remap_loc(node, _base), do: node

  defp file_line(_line, nil), do: nil
  defp file_line(line, %{line: base_line}), do: base_line + line

  defp file_column(_loc, nil), do: nil

  # Document line 1 is the only one a sigil's own prefix stands in front of.
  defp file_column(%{line: 1, column: column}, %{column: base}) when is_integer(column),
    do: base + column

  defp file_column(%{column: column}, %{continuation_column: base}) when is_integer(column),
    do: base + column

  defp file_column(_loc, _base), do: nil

  @doc """
  The file location a node was remapped to, or nil when it has none.
  """
  @spec loc(struct()) :: loc() | nil
  def loc(%{loc: %{line: line, column: column} = loc})
      when is_integer(line) and is_integer(column),
      do: %{line: line, column: column, file: Map.get(loc, :file)}

  def loc(_node), do: nil

  @doc """
  What `Module.create/3` is handed for a module generated from `loc`.

  Keeps the caller's `Macro.Env` — its aliases and tracers are what make the
  generated module compile the way the caller's own code would — and moves the
  line, and the file when the node names one. A spread mixes two documents into
  one tree and they may come from two files, so the file belongs to the node
  rather than to the compilation. `Module.create/3` records no column, so the
  column a `loc` carries is for whoever reads the node itself, a generation
  plugin above all. A node with no location keeps the caller's own, which is the
  `defgql`/`deffragment` itself.
  """
  @spec create_opts(Macro.Env.t(), loc() | nil) :: Macro.Env.t()
  def create_opts(%Macro.Env{} = caller_env, %{line: line, file: file}) when is_binary(file),
    do: %{caller_env | line: line, file: file}

  def create_opts(%Macro.Env{} = caller_env, %{line: line}), do: %{caller_env | line: line}
  def create_opts(%Macro.Env{} = caller_env, nil), do: caller_env
end
