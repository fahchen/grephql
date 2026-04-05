defmodule Grephql.Formatter do
  @moduledoc """
  Formatter plugin for the `~GQL` sigil.

  Formats GraphQL code inside `~GQL` sigils when running `mix format`.

  ## Setup

  Add to your `.formatter.exs`:

      [
        plugins: [Grephql.Formatter],
        # ...
      ]

  Or if using Grephql as a dependency:

      [
        import_deps: [:grephql],
        # ...
      ]
  """

  @behaviour Mix.Tasks.Format

  @impl Mix.Tasks.Format
  def features(_opts) do
    [sigils: [:GQL]]
  end

  @impl Mix.Tasks.Format
  def format(contents, opts) do
    case Grephql.Parser.parse(contents) do
      {:ok, document} ->
        formatted = Grephql.Printer.print(document)

        if opts[:opening_delimiter] in ["\"\"\"", "'''"] do
          formatted <> "\n"
        else
          formatted
        end

      {:error, _reason} ->
        contents
    end
  rescue
    # Parser.parse/1 raises FunctionClauseError on edge cases like empty strings
    FunctionClauseError -> contents
  end
end
