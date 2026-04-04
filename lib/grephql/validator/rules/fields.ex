defmodule Grephql.Validator.Rules.Fields do
  @moduledoc false

  alias Grephql.Language.Document
  alias Grephql.Language.InlineFragment
  alias Grephql.Language.OperationDefinition
  alias Grephql.Language.SelectionSet
  alias Grephql.Schema
  alias Grephql.Schema.TypeRef
  alias Grephql.Validator.Context

  @spec validate(Document.t(), Context.t()) :: Context.t()
  def validate(%Document{definitions: definitions}, %Context{} = ctx) do
    operations = Enum.filter(definitions, &match?(%OperationDefinition{}, &1))

    Enum.reduce(operations, ctx, fn op, acc ->
      root_type_name = root_type_name(acc.schema, op.operation)
      validate_selection_set(acc, op.selection_set, root_type_name)
    end)
  end

  defp root_type_name(%Schema{} = schema, :query), do: schema.query_type
  defp root_type_name(%Schema{} = schema, :mutation), do: schema.mutation_type
  defp root_type_name(%Schema{} = schema, :subscription), do: schema.subscription_type
  defp root_type_name(_, _), do: nil

  defp validate_selection_set(ctx, nil, _), do: ctx
  defp validate_selection_set(ctx, %SelectionSet{selections: []}, _), do: ctx

  defp validate_selection_set(ctx, %SelectionSet{selections: selections}, type_name) do
    Enum.reduce(selections, ctx, fn selection, acc ->
      validate_selection(acc, selection, type_name)
    end)
  end

  defp validate_selection(ctx, %Grephql.Language.Field{} = field, type_name) do
    if introspection_field?(field.name) do
      ctx
    else
      validate_field(ctx, field, type_name)
    end
  end

  defp validate_selection(ctx, %InlineFragment{} = fragment, _) do
    fragment_type_name =
      if fragment.type_condition, do: fragment.type_condition.name, else: nil

    validate_selection_set(ctx, fragment.selection_set, fragment_type_name)
  end

  defp validate_selection(ctx, _, _), do: ctx

  defp validate_field(ctx, field, type_name) when is_binary(type_name) do
    case Schema.get_type(ctx.schema, type_name) do
      {:ok, schema_type} ->
        case Map.fetch(schema_type.fields, field.name) do
          {:ok, schema_field} ->
            validate_sub_selections(ctx, field, schema_field.type)

          :error ->
            Context.add_error(
              ctx,
              "field \"#{field.name}\" does not exist on type \"#{type_name}\"",
              line: loc_line(field)
            )
        end

      :error ->
        ctx
    end
  end

  defp validate_field(ctx, _, _), do: ctx

  defp validate_sub_selections(ctx, field, type_ref) do
    named_type = unwrap_type(type_ref)
    kind = resolve_type_kind(ctx.schema, named_type)
    has_sels = has_selections?(field.selection_set)

    check_kind(ctx, field, kind, has_sels, named_type)
  end

  defp check_kind(ctx, field, :scalar, true, _) do
    Context.add_error(
      ctx,
      "field \"#{field.name}\" is a scalar and cannot have sub-selections",
      line: loc_line(field)
    )
  end

  defp check_kind(ctx, _, :scalar, false, _), do: ctx

  defp check_kind(ctx, field, :enum, true, _) do
    Context.add_error(
      ctx,
      "field \"#{field.name}\" is an enum and cannot have sub-selections",
      line: loc_line(field)
    )
  end

  defp check_kind(ctx, _, :enum, false, _), do: ctx

  defp check_kind(ctx, field, composite, false, _)
       when composite in [:object, :interface, :union] do
    Context.add_error(
      ctx,
      "field \"#{field.name}\" is an object type and requires a sub-selection",
      line: loc_line(field)
    )
  end

  defp check_kind(ctx, field, composite, true, named_type)
       when composite in [:object, :interface, :union] do
    type_name = if named_type, do: named_type.name, else: nil
    validate_selection_set(ctx, field.selection_set, type_name)
  end

  defp check_kind(ctx, _, _, _, _), do: ctx

  defp unwrap_type(%TypeRef{kind: kind, of_type: of_type})
       when kind in [:non_null, :list] and not is_nil(of_type) do
    unwrap_type(of_type)
  end

  defp unwrap_type(%TypeRef{} = ref), do: ref
  defp unwrap_type(nil), do: nil

  defp resolve_type_kind(%Schema{} = schema, %TypeRef{name: name}) when is_binary(name) do
    case Schema.get_type(schema, name) do
      {:ok, type} -> type.kind
      :error -> nil
    end
  end

  defp resolve_type_kind(_, _), do: nil

  defp has_selections?(%SelectionSet{selections: [_ | _]}), do: true
  defp has_selections?(_), do: false

  defp introspection_field?("__typename"), do: true
  defp introspection_field?("__type"), do: true
  defp introspection_field?("__schema"), do: true
  defp introspection_field?(_), do: false

  defp loc_line(%{loc: %{line: line}}) when is_integer(line), do: line
  defp loc_line(_), do: nil
end
