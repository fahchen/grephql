defmodule TypedGql.Test.ClientModuleGenerationPlugin do
  @moduledoc false
  use TypedGql.Generation.Plugin

  alias TypedGql.Generation.Field
  alias TypedGql.Generation.Schema

  # Renames every `name` field to `display_name`. A rename is observable at
  # runtime — the decoded struct exposes the new key, sourced from the original
  # "name" — unlike forced nullability, whose effect lives only in the @type
  # (not introspectable on generated modules). Proves a user plugin reaches the
  # pipeline via use TypedGql's :generation_plugins.
  @impl TypedGql.Generation.Plugin
  def after_resolve(tree, _context), do: rename(tree)

  defp rename(%Schema{} = node) do
    %{
      node
      | fields:
          Enum.map(node.fields, fn
            %Field{name: :name} = field -> %{field | name: :display_name}
            field -> field
          end),
        children: Enum.map(node.children, &rename/1)
    }
  end
end
