defmodule TypedGql.SourceAnchor do
  @moduledoc false
  # Maps a position inside a compiled GraphQL document onto the position in the
  # Elixir file that wrote it, so a generated module points at the selection
  # that produced it rather than at the whole `defgql`.
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
  What the document's line 1, column 1 sits at, or nil when the document does
  not map onto a file. `:file` is set only when that is not the caller's own —
  a macro that emitted the `defgql` with `quote location: :keep`.
  """
  @type base() ::
          %{line: non_neg_integer(), column: non_neg_integer(), file: binary() | nil} | nil

  @typedoc "A location in the source file, once `remap/2` has rewritten it."
  @type loc() :: %{line: pos_integer(), column: pos_integer()}

  @heredoc_delimiter ~s(""")
  @string_delimiter ~s(")

  # `~GQL` plus the one delimiter character after it: what sits between the
  # column the sigil opens on and the column its content starts at.
  @sigil_prefix_width String.length("~GQL") + 1

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
    with {:ok, origin} <- origin(sigil_meta),
         {:ok, delimiter} <- Keyword.fetch(sigil_meta, :delimiter) do
      document_start(delimiter, origin, sigil_meta, binary_meta)
    else
      _other -> nil
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
    case {Keyword.get(sigil_meta, :column), Keyword.get(sigil_meta, :keep)} do
      {_column, {file, line}} when is_binary(file) and is_integer(line) ->
        {:ok, %{line: line, file: file}}

      {column, _keep} when is_integer(column) ->
        with {:ok, line} <- Keyword.fetch(sigil_meta, :line),
             true <- is_integer(line) do
          {:ok, %{line: line, column: column, file: nil}}
        else
          _other -> :error
        end

      _other ->
        :error
    end
  end

  # A heredoc's content starts on the line after the sigil, stripped of the same
  # indentation on every line. A one-line sigil's starts on that same line, five
  # characters along: `~GQL` and its delimiter. Any other delimiter is not one of
  # the two shapes the arithmetic knows, so it is refused rather than guessed at.
  defp document_start(@heredoc_delimiter, origin, _sigil_meta, binary_meta) do
    %{
      line: origin.line,
      column: Keyword.get(binary_meta, :indentation, 0),
      file: Map.get(origin, :file)
    }
  end

  defp document_start(@string_delimiter, %{column: column} = origin, _sigil_meta, _binary_meta)
       when is_integer(column) do
    %{
      line: origin.line - 1,
      column: column + @sigil_prefix_width - 1,
      file: Map.get(origin, :file)
    }
  end

  defp document_start(_delimiter, _origin, _sigil_meta, _binary_meta), do: nil

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
    %{node | loc: %{loc | line: file_line(line, base), column: file_column(loc, base)}}
  end

  defp remap_loc(node, _base), do: node

  defp file_line(_line, nil), do: nil
  defp file_line(line, %{line: base_line}), do: base_line + line

  defp file_column(_loc, nil), do: nil
  defp file_column(%{column: column}, %{column: base}) when is_integer(column), do: base + column
  defp file_column(_loc, _base), do: nil

  @doc """
  The file location a node was remapped to, or nil when it has none.
  """
  @spec loc(struct()) :: loc() | nil
  def loc(%{loc: %{line: line, column: column}})
      when is_integer(line) and line > 0 and is_integer(column),
      do: %{line: line, column: column}

  def loc(_node), do: nil

  @doc """
  What `Module.create/3` is handed for a module generated from `loc`.

  Keeps the caller's `Macro.Env` — its aliases and tracers are what make the
  generated module compile the way the caller's own code would — and moves the
  line onto the node's. `Module.create/3` records no column, so the column a
  `loc` carries is for whoever reads the node itself, a generation plugin above
  all. A node with no location keeps the caller's line, which is the
  `defgql`/`deffragment` itself.
  """
  @spec create_opts(Macro.Env.t(), loc() | nil) :: Macro.Env.t()
  def create_opts(%Macro.Env{} = caller_env, %{line: line}), do: %{caller_env | line: line}
  def create_opts(%Macro.Env{} = caller_env, nil), do: caller_env

  @doc """
  The caller env the whole document's modules are created from.

  A document a macro emitted with `quote location: :keep` was written in that
  macro's file, not in the one calling it, and its node lines count from there —
  so the env every module is built on has to name that file, once, rather than
  each `loc` carrying it.
  """
  @spec document_env(Macro.Env.t(), base()) :: Macro.Env.t()
  def document_env(%Macro.Env{} = caller_env, %{file: file}) when is_binary(file),
    do: %{caller_env | file: file}

  def document_env(%Macro.Env{} = caller_env, _base), do: caller_env
end
