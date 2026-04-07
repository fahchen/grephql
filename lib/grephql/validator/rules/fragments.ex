defmodule Grephql.Validator.Rules.Fragments do
  @moduledoc false

  alias Grephql.Language.Document
  alias Grephql.Language.Field
  alias Grephql.Language.Fragment
  alias Grephql.Language.InlineFragment
  alias Grephql.Language.OperationDefinition
  alias Grephql.Language.SelectionSet
  alias Grephql.Schema
  alias Grephql.Validator.Context
  alias Grephql.Validator.Helpers

  @spec validate(Document.t(), Context.t()) :: Context.t()
  def validate(%Document{definitions: definitions}, %Context{} = ctx) do
    ctx =
      definitions
      |> Enum.filter(&match?(%OperationDefinition{}, &1))
      |> Enum.reduce(ctx, fn op, acc ->
        root_type_name = Helpers.root_type_name(acc.schema, op.operation)
        validate_selection_set(acc, op.selection_set, root_type_name, acc.schema)
      end)

    definitions
    |> Enum.filter(&match?(%Fragment{}, &1))
    |> Enum.reduce(ctx, fn frag, acc ->
      frag_type = frag.type_condition.name
      acc = validate_fragment_type_condition(acc, frag, frag_type)
      validate_selection_set(acc, frag.selection_set, frag_type, acc.schema)
    end)
  end

  defp validate_fragment_type_condition(ctx, frag, type_name) do
    case Schema.get_type(ctx.schema, type_name) do
      {:ok, %{kind: kind}} when kind in [:object, :interface, :union] ->
        ctx

      {:ok, %{kind: kind}} ->
        Context.add_error(
          ctx,
          "fragment \"#{frag.name}\" cannot be defined on #{kind} type \"#{type_name}\"",
          frag
        )

      :error ->
        Context.add_error(
          ctx,
          "type \"#{type_name}\" in fragment \"#{frag.name}\" does not exist in the schema",
          frag
        )
    end
  end

  defp validate_selection_set(ctx, nil, _parent_type, _schema), do: ctx
  defp validate_selection_set(ctx, %SelectionSet{selections: []}, _parent_type, _schema), do: ctx

  defp validate_selection_set(ctx, %SelectionSet{selections: sels}, parent_type, schema) do
    Enum.reduce(sels, ctx, fn sel, acc ->
      validate_selection(acc, sel, parent_type, schema)
    end)
  end

  defp validate_selection(ctx, %Field{} = field, parent_type, schema) do
    child_type = Helpers.resolve_field_type(schema, parent_type, field.name)
    validate_selection_set(ctx, field.selection_set, child_type, schema)
  end

  defp validate_selection(ctx, %InlineFragment{type_condition: nil} = frag, parent_type, schema) do
    validate_selection_set(ctx, frag.selection_set, parent_type, schema)
  end

  defp validate_selection(ctx, %InlineFragment{} = frag, parent_type, schema) do
    frag_type = frag.type_condition.name

    ctx
    |> validate_type_condition(frag, frag_type, parent_type, schema)
    |> validate_selection_set(frag.selection_set, frag_type, schema)
  end

  defp validate_selection(ctx, _selection, _parent_type, _schema), do: ctx

  defp validate_type_condition(ctx, frag, type_name, parent_type, schema) do
    case Schema.get_type(schema, type_name) do
      {:ok, _type} ->
        check_type_applicability(ctx, frag, type_name, parent_type, schema)

      :error ->
        Context.add_error(
          ctx,
          "type \"#{type_name}\" in type condition does not exist in the schema",
          frag
        )
    end
  end

  defp check_type_applicability(ctx, _frag, _type_name, nil, _schema), do: ctx

  defp check_type_applicability(ctx, frag, type_name, parent_type, schema) do
    if types_applicable?(type_name, parent_type, schema) do
      ctx
    else
      Context.add_error(
        ctx,
        "type \"#{type_name}\" is not applicable to \"#{parent_type}\"",
        frag
      )
    end
  end

  defp types_applicable?(type_name, parent_type, schema) do
    type_name == parent_type or
      member_of_abstract_type?(type_name, parent_type, schema) or
      share_abstract_member?(type_name, parent_type, schema)
  end

  defp member_of_abstract_type?(type_name, parent_type, schema) do
    case Schema.get_type(schema, parent_type) do
      {:ok, parent} -> type_name in parent.possible_types
      :error -> false
    end
  end

  defp share_abstract_member?(type_name, parent_type, schema) do
    type_possible = possible_types_for(type_name, schema)
    parent_possible = possible_types_for(parent_type, schema)

    not MapSet.disjoint?(MapSet.new(type_possible), MapSet.new(parent_possible))
  end

  defp possible_types_for(type_name, schema) do
    case Schema.get_type(schema, type_name) do
      {:ok, %{kind: kind} = type} when kind in [:union, :interface] ->
        type.possible_types

      {:ok, _type} ->
        [type_name]

      :error ->
        []
    end
  end
end
