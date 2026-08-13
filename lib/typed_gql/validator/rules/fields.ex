defmodule TypedGql.Validator.Rules.Fields do
  @moduledoc false

  alias TypedGql.Language.Document
  alias TypedGql.Schema
  alias TypedGql.Schema.TypeRef
  alias TypedGql.Validator.Context
  alias TypedGql.Validator.Helpers
  alias TypedGql.Validator.Traversal

  @spec validate(Document.t(), Context.t()) :: Context.t()
  def validate(%Document{definitions: definitions}, %Context{schema: schema} = ctx) do
    Traversal.traverse_all(definitions, schema, ctx, &validate_field/3)
  end

  # nil type_name means upstream type couldn't be resolved — already reported
  defp validate_field(_field, nil, ctx), do: ctx

  defp validate_field(field, type_name, ctx) when is_binary(type_name) do
    if introspection_field?(field.name) do
      ctx
    else
      check_field(ctx, field, type_name)
    end
  end

  defp check_field(ctx, field, type_name) do
    case Schema.get_type(ctx.schema, type_name) do
      {:ok, schema_type} ->
        case Map.fetch(schema_type.fields, field.name) do
          {:ok, schema_field} ->
            check_sub_selections(ctx, field, schema_field.type)

          :error ->
            Context.add_error(
              ctx,
              "field \"#{field.name}\" does not exist on type \"#{type_name}\"",
              field
            )
        end

      :error ->
        Context.add_error(
          ctx,
          "type \"#{type_name}\" is not defined in the schema",
          field
        )
    end
  end

  defp check_sub_selections(ctx, field, type_ref) do
    named_type = Helpers.unwrap_type(type_ref)

    case resolve_type_kind(ctx.schema, named_type) do
      # The schema declares the field but not the type it returns. Generation
      # would dereference the missing type and crash, so stop here instead.
      nil ->
        Context.add_error(
          ctx,
          "type \"#{named_type.name}\" of field \"#{field.name}\" is not defined in the schema",
          field
        )

      kind ->
        check_kind(ctx, field, kind, has_selections?(field.selection_set))
    end
  end

  defp check_kind(ctx, field, :scalar, true) do
    Context.add_error(
      ctx,
      "field \"#{field.name}\" is a scalar and cannot have sub-selections",
      field
    )
  end

  defp check_kind(ctx, _field, :scalar, false), do: ctx

  defp check_kind(ctx, field, :enum, true) do
    Context.add_error(
      ctx,
      "field \"#{field.name}\" is an enum and cannot have sub-selections",
      field
    )
  end

  defp check_kind(ctx, _field, :enum, false), do: ctx

  defp check_kind(ctx, field, composite, false)
       when composite in [:object, :interface, :union] do
    Context.add_error(
      ctx,
      "field \"#{field.name}\" is an object type and requires a sub-selection",
      field
    )
  end

  defp check_kind(ctx, _field, composite, true)
       when composite in [:object, :interface, :union] do
    ctx
  end

  defp check_kind(ctx, field, :input_object, _has_selections) do
    Context.add_error(
      ctx,
      "input type cannot be used as an output field type for \"#{field.name}\"",
      field
    )
  end

  defp resolve_type_kind(%Schema{} = schema, %TypeRef{name: name}) when is_binary(name) do
    case Schema.get_type(schema, name) do
      {:ok, type} -> type.kind
      :error -> nil
    end
  end

  defp has_selections?(%TypedGql.Language.SelectionSet{selections: [_head | _tail]}), do: true
  defp has_selections?(_selection_set), do: false

  defp introspection_field?("__typename"), do: true
  defp introspection_field?("__type"), do: true
  defp introspection_field?("__schema"), do: true
  defp introspection_field?(_name), do: false
end
