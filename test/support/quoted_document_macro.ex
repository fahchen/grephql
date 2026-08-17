defmodule TypedGql.Test.QuotedDocumentMacro do
  @moduledoc false
  # A `~GQL` document written inside a `quote` — the one shape where the sigil
  # meta lies. `quote` linifies what it carries to the line of the macro *call*,
  # so the delimiter survives while the line no longer belongs to the text; a
  # mapping that trusted the delimiter alone would anchor this document onto
  # whatever sits below the call in the calling file.

  defmacro define_shared_query(name) do
    quote do
      defgql(unquote(name), ~GQL"""
      query SharedQuery($id: ID!) {
        user(id: $id) {
          id
          profile {
            bio
          }
        }
      }
      """)
    end
  end
end
