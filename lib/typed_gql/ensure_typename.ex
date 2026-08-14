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
    # The aliased-__typename check follows spreads, and by this point the
    # document carries every fragment it uses — the macro appended them.
    fragments = Document.fragments_by_name(document)

    %{
      document
      | definitions: Enum.map(definitions, &transform_definition(&1, schema, fragments))
    }
  end

  defp transform_definition(%OperationDefinition{} = operation, schema, fragments) do
    root_type_name = Helpers.root_type_name(schema, operation.operation)

    %{
      operation
      | selection_set:
          transform_selection_set(operation.selection_set, root_type_name, schema, fragments)
    }
  end

  defp transform_definition(%Fragment{} = fragment, schema, fragments) do
    type_name = fragment.type_condition.name

    %{
      fragment
      | selection_set:
          transform_selection_set(fragment.selection_set, type_name, schema, fragments)
    }
  end

  # Type system definitions carry no selection sets.
  defp transform_definition(definition, _schema, _fragments), do: definition

  defp transform_selection_set(nil, _type_name, _schema, _fragments), do: nil

  defp transform_selection_set(%SelectionSet{} = selection_set, type_name, schema, fragments) do
    selections =
      Enum.map(selection_set.selections, &transform_selection(&1, type_name, schema, fragments))

    %{selection_set | selections: with_typename(selections, type_name, schema, fragments)}
  end

  defp transform_selection(%Field{} = field, type_name, schema, fragments) do
    child_type_name = Helpers.resolve_field_type(schema, type_name, field.name)

    %{
      field
      | selection_set:
          transform_selection_set(field.selection_set, child_type_name, schema, fragments)
    }
  end

  defp transform_selection(%InlineFragment{} = fragment, type_name, schema, fragments) do
    condition = if fragment.type_condition, do: fragment.type_condition.name, else: type_name

    %{
      fragment
      | selection_set:
          transform_selection_set(fragment.selection_set, condition, schema, fragments)
    }
  end

  # The fragment's own definition is transformed where it is defined.
  defp transform_selection(%FragmentSpread{} = spread, _type_name, _schema, _fragments),
    do: spread

  defp with_typename(selections, type_name, schema, fragments) do
    if Schema.abstract?(schema, type_name) and
         not Enum.any?(selections, &dispatchable_typename?/1),
       do: [%Field{name: "__typename"} | reject_typename_key!(selections, fragments)],
       else: selections
  end

  # `__typename: id` is legal GraphQL, but it takes the response key dispatch
  # needs. Adding ours anyway would put two different fields under one key in the
  # sent document, which the server rejects — so say what is wrong here instead.
  # Another copy of __typename itself is fine: same field, same key, they merge.
  #
  # The response-key space spans the nested inline fragments and spread bodies
  # too — their conditions all apply here (the validator checked), so a borrowed
  # key anywhere among them collides with the injected field on some member.
  # Field sub-selections are a different response level and are not entered.
  defp reject_typename_key!(selections, fragments) do
    if borrowed_typename_key?(selections, fragments, %{}) do
      raise CompileError,
        description:
          "\"__typename\" is aliased to another field on a union or interface " <>
            "selection, leaving no response key to dispatch on"
    end

    selections
  end

  defp borrowed_typename_key?(selections, fragments, seen) do
    Enum.any?(selections, fn
      %Field{alias: "__typename", name: name} ->
        name != "__typename"

      %InlineFragment{selection_set: %SelectionSet{selections: nested}} ->
        borrowed_typename_key?(nested, fragments, seen)

      %FragmentSpread{name: name} ->
        case {is_map_key(seen, name), fragments} do
          {false, %{^name => fragment}} ->
            borrowed_typename_key?(
              fragment.selection_set.selections,
              fragments,
              Map.put(seen, name, true)
            )

          # Already walked, or an unknown spread another stage reports.
          {_seen_or_missing, _fragments} ->
            false
        end

      _other_selection ->
        false
    end)
  end

  defp dispatchable_typename?(%Field{name: "__typename", alias: nil, directives: []}), do: true
  defp dispatchable_typename?(_selection), do: false
end
