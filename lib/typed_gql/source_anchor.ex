defmodule TypedGql.SourceAnchor do
  @moduledoc false
  # Maps a line inside a compiled GraphQL document onto the line of the Elixir
  # file that wrote it, so a generated module points at the selection that
  # produced it rather than at the whole `defgql`.
  #
  # A `~GQL` sigil is the only document form whose lines are known to be the
  # file's: the sigil's AST meta says which line it opens on, and its delimiter
  # says whether the document starts on that line (`~GQL"..."`) or on the next
  # one (`~GQL"""`). Any other form — a plain string, an interpolated one — can
  # carry newlines that were never written in this file, so it has no base line
  # and every node line is dropped rather than guessed: a wrong location sends
  # the reader to unrelated code, which is worse than the coarse `defgql` line
  # a dropped one falls back to.

  @typedoc "The file line the document's line 1 sits on, or nil when unmappable."
  @type base_line() :: non_neg_integer() | nil

  @typedoc "A location in the source file, once `remap/2` has rewritten it."
  @type loc() :: %{line: pos_integer()}

  @heredoc_delimiter ~s(""")
  @string_delimiter ~s(")

  @doc """
  The base line a `~GQL` sigil's document sits on, from the sigil's AST meta.

  `:line` is the line the sigil opens on, and `:delimiter` says whether its
  content starts on the next line (a heredoc) or on that very line. Any other
  delimiter — `~GQL(...)`, `'''` — and any meta without those two keys is
  unmappable rather than guessed at.
  """
  @spec base_line(keyword()) :: base_line()
  def base_line(sigil_meta) do
    if written_here?(sigil_meta) do
      case {Keyword.fetch(sigil_meta, :delimiter), Keyword.fetch(sigil_meta, :line)} do
        {{:ok, @heredoc_delimiter}, {:ok, line}} when is_integer(line) -> line
        {{:ok, @string_delimiter}, {:ok, line}} when is_integer(line) -> line - 1
        _other -> nil
      end
    end
  end

  # A sigil written inside a `quote` reaches the macro linified to the line of
  # the macro *call*, keeping its delimiter — so the delimiter alone would let a
  # document from another file anchor onto whatever happens to sit below the
  # call. The tokenizer records a `:column` only for a sigil it actually read at
  # this position, and drops it when `quote` rewrites the line, so its presence
  # is what says the line and the text belong to the same place.
  defp written_here?(sigil_meta) do
    is_integer(Keyword.get(sigil_meta, :column))
  end

  @doc """
  Rewrites every `loc` line under `node` from a document line to a file line.

  A nil `base_line` means the document does not map onto the file, so the lines
  are dropped instead: a node whose line is nil resolves to the caller's own
  location in `create_opts/2`.
  """
  @spec remap(struct(), base_line()) :: struct()
  def remap(%_struct{} = node, base_line) do
    node
    |> Map.from_struct()
    |> Enum.reduce(node, fn {key, value}, acc ->
      Map.put(acc, key, remap_value(value, base_line))
    end)
    |> remap_loc(base_line)
  end

  defp remap_value(%_struct{} = node, base_line), do: remap(node, base_line)

  defp remap_value(values, base_line) when is_list(values),
    do: Enum.map(values, &remap_value(&1, base_line))

  defp remap_value(other, _base_line), do: other

  # Only a node that carries a line is rewritten: `TypedGql.Language.Argument`
  # defaults its `loc` to a tuple, and every other node defaults the line to nil.
  defp remap_loc(%{loc: %{line: line} = loc} = node, base_line) when is_integer(line) do
    %{node | loc: %{loc | line: file_line(line, base_line)}}
  end

  defp remap_loc(node, _base_line), do: node

  defp file_line(_line, nil), do: nil
  defp file_line(line, base_line), do: base_line + line

  @doc """
  The file location a node was remapped to, or nil when it has none.
  """
  @spec loc(struct()) :: loc() | nil
  def loc(%{loc: %{line: line}}) when is_integer(line) and line > 0, do: %{line: line}
  def loc(_node), do: nil

  @doc """
  What `Module.create/3` is handed for a module generated from `loc`.

  Keeps the caller's `Macro.Env` — its aliases and tracers are what make the
  generated module compile the way the caller's own code would — and moves only
  the line. A node with no location keeps the caller's line, which is the
  `defgql`/`deffragment` itself.
  """
  @spec create_opts(Macro.Env.t(), loc() | nil) :: Macro.Env.t()
  def create_opts(%Macro.Env{} = caller_env, %{line: line}), do: %{caller_env | line: line}
  def create_opts(%Macro.Env{} = caller_env, nil), do: caller_env
end
