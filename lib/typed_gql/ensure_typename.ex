defmodule TypedGql.EnsureTypename do
  @moduledoc false

  # Union and interface results are decoded by dispatching on `__typename`
  # (`TypedGql.Types.Union`), so every abstract selection set needs one. Adding
  # it to the generated struct alone would not help: the server only returns
  # what the request asked for, so the field has to go into the document that
  # `TypedGql.Compiler` prints and sends.
  #
  # The copy added here is unaliased and undirected on purpose — an alias
  # changes the response key, and `@skip`/`@include` can remove it, and dispatch
  # happens before either is known.

  alias TypedGql.Language.Document
  alias TypedGql.Language.Field
  alias TypedGql.Language.Fragment
  alias TypedGql.Language.FragmentSpread
  alias TypedGql.Language.InlineFragment
  alias TypedGql.Language.OperationDefinition
  alias TypedGql.Language.SelectionSet
  alias TypedGql.Schema
  alias TypedGql.Validator.Helpers

  @spec transform(Document.t(), Schema.t()) :: Document.t()
  def transform(%Document{definitions: definitions} = document, %Schema{} = schema) do
    %{document | definitions: Enum.map(definitions, &transform_definition(&1, schema))}
  end

  defp transform_definition(%OperationDefinition{} = operation, schema) do
    root_type_name = Helpers.root_type_name(schema, operation.operation)

    %{
      operation
      | selection_set: transform_selection_set(operation.selection_set, root_type_name, schema)
    }
  end

  defp transform_definition(%Fragment{} = fragment, schema) do
    type_name = fragment.type_condition.name

    %{
      fragment
      | selection_set: transform_selection_set(fragment.selection_set, type_name, schema)
    }
  end

  # Type system definitions carry no selection sets.
  defp transform_definition(definition, _schema), do: definition

  defp transform_selection_set(nil, _type_name, _schema), do: nil

  defp transform_selection_set(%SelectionSet{} = selection_set, type_name, schema) do
    selections = Enum.map(selection_set.selections, &transform_selection(&1, type_name, schema))

    %{selection_set | selections: with_typename(selections, type_name, schema)}
  end

  defp transform_selection(%Field{} = field, type_name, schema) do
    child_type_name = Helpers.resolve_field_type(schema, type_name, field.name)

    %{
      field
      | selection_set: transform_selection_set(field.selection_set, child_type_name, schema)
    }
  end

  defp transform_selection(%InlineFragment{} = fragment, type_name, schema) do
    condition = if fragment.type_condition, do: fragment.type_condition.name, else: type_name

    %{
      fragment
      | selection_set: transform_selection_set(fragment.selection_set, condition, schema)
    }
  end

  # The fragment's own definition is transformed where it is defined.
  defp transform_selection(%FragmentSpread{} = spread, _type_name, _schema), do: spread

  defp with_typename(selections, type_name, schema) do
    if abstract?(schema, type_name) and not Enum.any?(selections, &dispatchable_typename?/1),
      do: [%Field{name: "__typename"} | selections],
      else: selections
  end

  defp abstract?(schema, type_name) do
    match?(
      {:ok, %{kind: kind}} when kind in [:union, :interface],
      Schema.get_type(schema, type_name)
    )
  end

  defp dispatchable_typename?(%Field{name: "__typename", alias: nil, directives: []}), do: true
  defp dispatchable_typename?(_selection), do: false
end
