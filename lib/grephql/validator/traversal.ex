defmodule Grephql.Validator.Traversal do
  @moduledoc false

  alias Grephql.Language.FragmentSpread
  alias Grephql.Language.InlineFragment
  alias Grephql.Language.OperationDefinition
  alias Grephql.Language.SelectionSet
  alias Grephql.Schema
  alias Grephql.Validator.Helpers

  @spec traverse_operations([Grephql.Language.definition_t()], Schema.t(), acc, field_callback) ::
          acc
        when acc: Grephql.Validator.Context.t(),
             field_callback: (Grephql.Language.Field.t(), String.t() | nil, acc -> acc)
  def traverse_operations(definitions, schema, acc, field_callback) do
    definitions
    |> Enum.filter(&match?(%OperationDefinition{}, &1))
    |> Enum.reduce(acc, fn op, ctx ->
      root_type_name = root_type_name(schema, op.operation)
      traverse_selection_set(op.selection_set, root_type_name, schema, ctx, field_callback)
    end)
  end

  defp root_type_name(%Schema{} = schema, :query), do: schema.query_type
  defp root_type_name(%Schema{} = schema, :mutation), do: schema.mutation_type
  defp root_type_name(%Schema{} = schema, :subscription), do: schema.subscription_type

  # nil type_name is valid — Operations rule already reported the missing root type
  defp traverse_selection_set(nil, _, _, ctx, _), do: ctx
  defp traverse_selection_set(%SelectionSet{selections: []}, _, _, ctx, _), do: ctx

  defp traverse_selection_set(%SelectionSet{selections: selections}, type_name, schema, ctx, cb) do
    Enum.reduce(selections, ctx, fn selection, acc ->
      traverse_selection(selection, type_name, schema, acc, cb)
    end)
  end

  defp traverse_selection(%Grephql.Language.Field{} = field, type_name, schema, ctx, cb) do
    ctx = cb.(field, type_name, ctx)
    child_type_name = resolve_field_type(schema, type_name, field.name)
    traverse_selection_set(field.selection_set, child_type_name, schema, ctx, cb)
  end

  defp traverse_selection(%InlineFragment{} = fragment, _, schema, ctx, cb) do
    fragment_type_name =
      if fragment.type_condition, do: fragment.type_condition.name, else: nil

    traverse_selection_set(fragment.selection_set, fragment_type_name, schema, ctx, cb)
  end

  # FragmentSpread is handled by a future fragment validation rule
  defp traverse_selection(%FragmentSpread{}, _, _, ctx, _), do: ctx

  # nil type_name means upstream field wasn't found — Fields rule already reported
  defp resolve_field_type(_, nil, _), do: nil

  defp resolve_field_type(schema, type_name, field_name) when is_binary(type_name) do
    case Schema.get_field(schema, type_name, field_name) do
      {:ok, schema_field} ->
        named = Helpers.unwrap_type(schema_field.type)
        if named, do: named.name, else: nil

      :error ->
        nil
    end
  end
end
