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
      root_type_name = Helpers.root_type_name(schema, op.operation)
      traverse_selection_set(op.selection_set, root_type_name, schema, ctx, field_callback)
    end)
  end

  # nil type_name is valid — Operations rule already reported the missing root type
  defp traverse_selection_set(nil, _type_name, _schema, ctx, _cb), do: ctx

  defp traverse_selection_set(%SelectionSet{selections: []}, _type_name, _schema, ctx, _cb),
    do: ctx

  defp traverse_selection_set(%SelectionSet{selections: selections}, type_name, schema, ctx, cb) do
    Enum.reduce(selections, ctx, fn selection, acc ->
      traverse_selection(selection, type_name, schema, acc, cb)
    end)
  end

  defp traverse_selection(%Grephql.Language.Field{} = field, type_name, schema, ctx, cb) do
    ctx = cb.(field, type_name, ctx)
    child_type_name = Helpers.resolve_field_type(schema, type_name, field.name)
    traverse_selection_set(field.selection_set, child_type_name, schema, ctx, cb)
  end

  defp traverse_selection(%InlineFragment{} = fragment, _type_name, schema, ctx, cb) do
    fragment_type_name =
      if fragment.type_condition, do: fragment.type_condition.name, else: nil

    traverse_selection_set(fragment.selection_set, fragment_type_name, schema, ctx, cb)
  end

  # FragmentSpread is handled by a future fragment validation rule
  defp traverse_selection(%FragmentSpread{}, _type_name, _schema, ctx, _cb), do: ctx
end
