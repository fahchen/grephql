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

  # `location: :keep` is the one form a document survives being moved in: the
  # meta names the file and line it was really written at, so its modules point
  # here rather than at whoever called the macro. The line each one belongs on
  # is recorded beside it, since the caller cannot know them.
  @kept_query __ENV__.line + 4

  defmacro define_kept_query(name) do
    quote location: :keep do
      defgql(unquote(name), ~GQL"""
      query KeptQuery($id: ID!) {
        user(id: $id) {
          profile {
            bio
          }
        }
      }
      """)
    end
  end

  # A fragment written here and spread by a query in another file: the modules
  # its selections name belong to this file, while the query's own belong to the
  # caller's. One compilation, two files.
  @kept_fragment __ENV__.line + 4

  defmacro define_kept_fragment do
    quote location: :keep do
      deffragment(~GQL"""
      fragment KeptBits on User {
        profile {
          bio
        }
      }
      """)
    end
  end

  @doc "Where in this file the kept fragment's modules should say they come from."
  @spec kept_fragment_lines(module()) :: %{module() => pos_integer()}
  def kept_fragment_lines(client) do
    %{
      Module.safe_concat([client, Fragments, KeptBits]) => @kept_fragment + 1,
      Module.safe_concat([client, Fragments, KeptBits, Profile]) => @kept_fragment + 2
    }
  end

  @doc "Where in this file the kept query's modules should say they come from."
  @spec kept_lines(module()) :: %{module() => pos_integer()}
  def kept_lines(client) do
    %{
      Module.safe_concat([client, KeptQuery, Result]) => @kept_query + 1,
      Module.safe_concat([client, KeptQuery, Result, User]) => @kept_query + 2,
      Module.safe_concat([client, KeptQuery, Result, User, Profile]) => @kept_query + 3
    }
  end
end
